"""Nontrivial negative checks for geometry validation and contact computation."""
import importlib.util
import math
from pathlib import Path
import sys
import tempfile
import unittest
import subprocess
import fcntl

TOOLS=Path(__file__).resolve().parents[1]/'tools'
sys.path.insert(0,str(TOOLS))
from cam_sim import contact_height,load_geometry
from check_stl import inspect


def ascii_stl(triangles,path):
    path.write_text('solid test\n'+''.join('facet normal 0 0 0\nouter loop\n'+''.join('vertex %s %s %s\n'%p for p in tri)+'endloop\nendfacet\n' for tri in triangles)+'endsolid test\n')


TETRA=[((0,0,0),(0,1,0),(1,0,0)),((0,0,0),(1,0,0),(0,0,1)),((0,0,0),(0,0,1),(0,1,0)),((1,0,0),(0,1,0),(0,0,1))]


class MeshChecks(unittest.TestCase):
    def check_triangles(self,triangles):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.stl';ascii_stl(triangles,p);return inspect(p)
    def test_watertight_positive_tetra_on_bed(self):
        self.assertTrue(self.check_triangles(TETRA)['pass'])
    def test_missing_triangle_rejected(self):
        self.assertFalse(self.check_triangles(TETRA[:-1])['pass'])
    def test_inverted_face_rejected(self):
        self.assertFalse(self.check_triangles([tuple(reversed(TETRA[0]))]+TETRA[1:])['pass'])
    def test_disconnected_closed_parts_rejected(self):
        second=[tuple((x+3,y,z) for x,y,z in tri) for tri in TETRA]
        self.assertEqual(self.check_triangles(TETRA+second)['components'],2)
        self.assertFalse(self.check_triangles(TETRA+second)['pass'])
    def test_floating_mesh_rejected(self):
        self.assertFalse(self.check_triangles([tuple((x,y,z+1) for x,y,z in tri) for tri in TETRA])['pass'])
    def test_empty_rejected(self):
        with self.assertRaises(ValueError): self.check_triangles([])


class FollowerChecks(unittest.TestCase):
    def test_contact_checks_segment_interior(self):
        # Vertices both outside the flat tip; maximum lies at x=0.3 along edge.
        polygon=[(-2,1),(2,3),(2,-3),(-2,-3)]
        self.assertAlmostEqual(contact_height(polygon,0,2.1,.3,30),2.15)
    def test_tip_width_changes_actual_contact(self):
        polygon=[(-2,1),(2,3),(2,-3),(-2,-3)]
        self.assertGreater(contact_height(polygon,0,2.1,.6,30),contact_height(polygon,0,2.1,.1,30))
    def test_actual_cad_polygon_changes_by_band(self):
        params,profiles=load_geometry()
        self.assertNotEqual(profiles[(0,0)],profiles[(0,1)])
        self.assertEqual(len(profiles),12)
        # All four coincident lobes would pass a naive single-cam test, fail this.
        base=params[3]
        heights=[contact_height(profiles[(0,b)],58,2.1,.3,30)-base for b in range(4)]
        self.assertAlmostEqual(heights[1],2,places=4)
        self.assertTrue(all(abs(h)<.02 for b,h in enumerate(heights) if b!=1))

    def test_175_degree_profile_keeps_full_stroke_and_neutral_gaps(self):
        params,profiles=load_geometry()
        bands,gaps,tap,base,stroke,pin_r,tip_r,half_angle,*_=params
        self.assertEqual(bands,[0,58,117,175])
        self.assertEqual(gaps,[29,87.5,146])
        self.assertEqual(stroke,2)
        for variant in range(3):
            for band,angle in enumerate(bands):
                self.assertAlmostEqual(contact_height(profiles[(variant,band)],angle,pin_r,tip_r,half_angle)-base,2,places=4)
            for angle in gaps:
                self.assertLess(max(contact_height(profiles[(variant,b)],angle,pin_r,tip_r,half_angle)-base for b in range(4)),.03)
    def test_old_wide_lobe_fails_120_degree_neutral_gap(self):
        # Finite cone contact persists beyond the radial lobe: shortening angles
        # without changing the manufactured polygon raises both adjacent pins.
        params,profiles=load_geometry(('cam_half_width=24','band_angles=[0,40,80,120]','gap_angles=[20,60,100]'))
        base=params[3]
        for variant in range(3):
            lifts=[contact_height(profiles[(variant,b)],20,2.1,.3,30)-base for b in range(2)]
            self.assertTrue(all(lift>.8 for lift in lifts))


class NominalFitChecks(unittest.TestCase):
    def probe(self,*overrides):
        with tempfile.TemporaryDirectory() as d:
            return subprocess.run(['openscad','-o',str(Path(d)/'fit.csg'),*overrides,str(TOOLS/'fit_probe.scad')],capture_output=True,text=True,timeout=20)
    def test_declared_nominal_envelopes_fit(self):
        r=self.probe();self.assertEqual(r.returncode,0);self.assertNotIn('ERROR:',r.stderr);self.assertIn('NOMINAL_FIT',r.stderr)
    def test_servo_intruding_wall_is_rejected(self):
        r=self.probe('-D','servo_case_depth=40');self.assertIn('ERROR:',r.stderr)
    def test_unmeasured_print_gate_is_closed(self):
        r=subprocess.run([sys.executable,str(TOOLS/'build.py'),'--print-ready'],capture_output=True,text=True,timeout=20)
        self.assertEqual(r.returncode,2);self.assertIn('UNMEASURED',r.stderr)
    def test_concurrent_output_writer_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with (Path(d)/'.build.lock').open('a') as f:
                fcntl.flock(f.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
                r=subprocess.run([sys.executable,str(TOOLS/'build.py'),'--fast','--output',d],capture_output=True,text=True,timeout=20)
                self.assertEqual(r.returncode,2);self.assertIn('another CAD build',r.stderr)


if __name__=='__main__': unittest.main()
