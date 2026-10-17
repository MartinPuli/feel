import io
from pathlib import Path
import sys
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import images  # noqa: E402


def jpeg(width: int, height: int, **save_kwargs) -> bytes:
    out = io.BytesIO()
    Image.new('RGB', (width, height), (200, 120, 40)).save(out, format='JPEG', **save_kwargs)
    return out.getvalue()


def described(data: bytes):
    with Image.open(io.BytesIO(data)) as image:
        return image.format, image.size


class PhoneJpegTests(unittest.TestCase):
    """The evaluation must send the photo the phone would send: long side at most 1024 px, JPEG quality 0.6."""

    def test_large_photo_is_scaled_to_a_1024_long_side(self):
        self.assertEqual(described(images.phone_jpeg(jpeg(4032, 3024))), ('JPEG', (1024, 768)))

    def test_small_photo_is_not_enlarged(self):
        self.assertEqual(described(images.phone_jpeg(jpeg(640, 480))), ('JPEG', (640, 480)))

    def test_camera_orientation_tag_is_applied(self):
        # A portrait phone photo is stored sideways with orientation 6; the model must see it upright, as the labeler did.
        exif = Image.Exif()
        exif[0x0112] = 6
        self.assertEqual(described(images.phone_jpeg(jpeg(4032, 3024, exif=exif.tobytes()))), ('JPEG', (768, 1024)))

    def test_quality_matches_the_phone(self):
        sent = Image.open(io.BytesIO(images.phone_jpeg(jpeg(1024, 768))))
        self.assertEqual(sent.quantization, Image.open(io.BytesIO(jpeg(1024, 768, quality=60))).quantization)
        self.assertNotEqual(sent.quantization, Image.open(io.BytesIO(jpeg(1024, 768, quality=90))).quantization)


if __name__ == '__main__':
    unittest.main()
