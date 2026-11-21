import os
import tempfile
import unittest

import film_audit

FILM = '''return {
	w=1366,h=768,fps=30,
	chars={
	[1]={k="shape",a=1,x=1,y=1658,w=1024,h=576,ox=0,oy=0,dw=1366,dh=768,p={1366,0}},
	[2]={k="sprite",n=1,labels={},frames={
		{{d=1,c=1,m={1,0,0,1,0,0}}}
	}},
	[3]={k="sprite",n=15,labels={["close"]=2},frames={
		{{d=1,c=2,m={1,0,0,1,0,0}},a={{"stop"}}},
		{{d=1,mv=true}}
	}},
	[4]={k="shape",a=1,x=1,y=1,w=8,h=8,ox=0,oy=0,dw=40,dh=40},
	[5]={k="sprite",n=1,labels={},frames={
		{{d=1,c=4,m={1,0,0,1,0,0}}}
	}},
	[6]={k="sprite",n=3,labels={},frames={
		{{d=1,c=3,n="Alpha"},{d=3,c=5,n="Small"}}
	}}
	},
	root={
		{{d=1,c=6,n="Root",m={1,0,0,1,0,0}}}
	}
}
'''


class FilmAuditTest(unittest.TestCase):
    def test_a_full_screen_shape_is_found_with_the_clips_that_hold_it(self):
        film = film_audit.parse_film(FILM)
        big, chains = film_audit.fullscreen_chains(film, (1366, 768), 0.35)
        self.assertEqual(big, [1])
        self.assertEqual(chains, [["6:Root", "3:Alpha", "2", "1"]])

    def test_a_small_shape_is_not_listed(self):
        film = film_audit.parse_film(FILM)
        big, _ = film_audit.fullscreen_chains(film, (1366, 768), 0.35)
        self.assertNotIn(4, big)

    def test_a_script_that_reaches_another_clip_is_a_gap_and_a_plain_stop_is_not(self):
        self.assertTrue(film_audit.unconvertible('_root.Root.Alpha.gotoAndPlay("close");'))
        self.assertTrue(film_audit.unconvertible('fscommand("closeBinoculars");'))
        self.assertTrue(film_audit.unconvertible("this.DegreeN.text = _root.DegreeN.text;"))
        self.assertFalse(film_audit.unconvertible("stop();"))
        self.assertFalse(film_audit.unconvertible("play();"))
        self.assertFalse(film_audit.unconvertible('Icon.gotoAndStop("on");'))
        self.assertFalse(film_audit.unconvertible("}"))
        # the colour copy of every Colorset clip is the film's "color" action
        self.assertFalse(film_audit.unconvertible("color2.setRGB(color1.getRGB());"))

    def test_a_statement_that_reaches_outside_the_clip_is_told_from_a_local_one(self):
        self.assertTrue(film_audit.reaches_outside('_root.Root.Alpha.gotoAndPlay("close");'))
        self.assertTrue(film_audit.reaches_outside('fscommand("closeBinoculars");'))
        self.assertTrue(film_audit.reaches_outside("_parent.Friendly._visible = false;"))
        self.assertFalse(film_audit.reaches_outside("this.Indicator._visible = false;"))

    def test_the_gaps_come_with_their_sprite_and_frame(self):
        with tempfile.TemporaryDirectory() as folder:
            frame = os.path.join(folder, "DefineSprite_128", "frame_26")
            os.makedirs(frame)

            with open(os.path.join(frame, "DoAction.as"), "w") as handle:
                handle.write('play();\n_root.Root.Alpha.gotoAndPlay("close");\n')

            self.assertEqual(film_audit.script_gaps(folder), [("DefineSprite_128/frame_26", '_root.Root.Alpha.gotoAndPlay("close");')])


if __name__ == "__main__":
    unittest.main()
