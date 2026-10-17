#include "feel/single_live.hpp"
#include <cassert>
#include <cstdio>
int main() {
    feel::Controller c;
    assert(feel::singleWidePulse(c.snapshot()) == 0);
    c.connect(0);
    feel::Packet p; p.bands[3] = 1;
    auto bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),1)==feel::Result::Ok);
    auto s=c.snapshot();
    unsigned previous=0;
    for(unsigned us=650;us<=2500;++us) {
        s.pulses[3]=us;
        unsigned wide=feel::singleWidePulse(s);
        assert(wide>=650 && wide<=2500 && wide>=previous);
        assert(wide == (us > 2341 ? 2500 : us+159));
        assert(feel::singleLivePulse(s)==wide); // Positive trim once; bounded at upper end.
        previous=wide;
    }
    s.pulses[3]=650; assert(feel::singleWidePulse(s)==809);
    s.pulses[3]=1500; assert(feel::singleWidePulse(s)==1659);
    s.pulses[3]=2500; assert(feel::singleWidePulse(s)==2500);
    s.pulses[3]=2501; assert(feel::singleWidePulse(s)==0);
    s.pulses[3]=649; assert(feel::singleWidePulse(s)==0);
    p.sequence=1; p.bands.fill(0); bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),2)==feel::Result::Ok);
    assert(feel::singleWidePulse(c.snapshot())==1116);
    s=c.snapshot(); s.benchArmed=true; assert(feel::singleWidePulse(s)==0);
    s=c.snapshot(); s.rawPulse=true; assert(feel::singleWidePulse(s)==0);
    c.tick(502); assert(feel::singleWidePulse(c.snapshot())==0);
    p.sequence=2; bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),502)==feel::Result::Ok);
    c.disconnect(503); assert(feel::singleWidePulse(c.snapshot())==0);
    puts("PASS wide-test mapping, shared controller pass-through, invalid bounds, STOP, bench/raw rejection, expiry, disconnect");
}
