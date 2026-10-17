"""Adversarial synthetic checks only: no host or actual capture claims."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('palette_oracle',Path(__file__).with_name('palette_oracle.py'))
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)


def box(x,y,w,h):
    return dict(x=x,y=y,width=w,height=h)


def paint(i,kind,bounds,color,text=None):
    item = dict(id=i,kind=kind,bounds=copy.deepcopy(bounds),color=dict(zip(('red','green','blue','alpha'),(*color,255))),
                transform=dict(a=1,b=0,c=0,d=1,tx=0,ty=0),opacity=1,clip_chain_id=None)
    if text is not None:
        item.update(text=text,font_size=14,text_origin=dict(x=bounds['x'],y=bounds['y']))
    return item


def marker(phase=0):
    tokens = ('none','none','light','light','dark','none')
    counts = (0,1,1,2,2,2)
    actions = ('increment','palette-toggle','increment','palette-toggle','palette-toggle')
    m = dict(fixture='palette',phase=phase,count=counts[phase],value=counts[phase],releases=phase,
        actions=['Activate']*phase,enabled=True,loading=False,pressed=False,focused=phase in (1,3),
        root=box(0,0,120,80),scale=1,button=box(4,30,50,30),buttonLabel=box(15,40,25,10),heading=box(4,2,40,10),
        palette=dict(token=tokens[phase],toggleToken=tokens[phase],toggleEnabled=True,toggleLoading=False,hovered=phase in (1,3),toggleHovered=phase in (2,4,5),
            togglePressed=False,toggleFocused=phase in (2,4,5),toggle=box(60,30,50,30),toggleLabel=box(70,40,25,10),
            buttonId=10,toggleId=20,revision=phase*3+1,actionKeys=list(actions[:phase])),
        frame=dict(path=f'frame-{phase}.ppm',width=120,height=80,scale=1))
    m['inputTrace'] = dict(revision=phase*3+1,throughSequence=phase+1,events=[dict(sequence=i+1,scale=1,consumed=False,dispatched=False,beforeDispatch=0,afterDispatch=0,kind='other-window') for i in range(phase+1)])
    items = [paint(1,'quad',m['root'],(245,247,250)),paint(2,'text_run',m['heading'],(242,246,250),'Shared palette'),
             paint(3,'text_run',box(4,15,30,10),(242,246,250),f'Count: {counts[phase]}')]
    for bid,b,lb,label,state in oracle._buttons(m):
        # Independent fixture table for states actually used by this sequence.
        light = tokens[phase] == 'light'
        border = ((35,110,210) if light else (98,170,255)) if state['focused'] else ((130,146,164) if light else (102,126,150))
        fill = ((226,237,250) if light else (48,91,137)) if state['hovered'] else ((245,248,252) if light else (42,71,101))
        fg = (25,43,62) if light else (242,246,250)
        inset = 2 if state['focused'] else 1
        items += [paint(bid+1,'quad',b,border),paint(bid+2,'quad',box(b['x']+inset,b['y']+inset,b['width']-2*inset,b['height']-2*inset),fill),paint(bid+3,'text_run',lb,fg,label)]
    m['scene'] = dict(schema_version=1,viewport=m['root'].copy(),scale=1,resources=[],clip_chains=[],items=items)
    return m


class SyntheticImage:
    def __init__(self,m):
        self.width,self.height = 120,80
        self.data = [[(0,0,0)]*self.width for _ in range(self.height)]
        for item in m['scene']['items']:
            b = item['bounds']
            c = tuple(item['color'][k] for k in ('red','green','blue'))
            if item['kind'] == 'quad':
                for y in range(b['y'],b['y']+b['height']):
                    for x in range(b['x'],b['x']+b['width']): self.data[y][x] = c
            else:
                for x in range(b['x']+2,b['x']+6): self.data[b['y']+2][x] = c
    def pixel(self,x,y): return self.data[y][x]


class PaletteTests(unittest.TestCase):
    def test_six_synthetic_frames_and_sequence(self):
        frames = [marker(p) for p in range(6)]
        oracle.validate_palette_sequence(frames)
        for m in frames:
            self.assertEqual(len(oracle.inspect_palette_pixels(SyntheticImage(m),m)),2)

    def test_retained_dual_hover_scene_and_pixels(self):
        m = marker(4)
        m['palette']['hovered'] = True
        m['scene']['items'][4]['color'].update(red=48,green=91,blue=137)
        oracle.validate_palette_marker(m,4)
        image = SyntheticImage(m)
        self.assertEqual(len(oracle.inspect_palette_pixels(image,m)),2)
        forged = copy.deepcopy(m)
        forged['palette']['hovered'] = False
        with self.assertRaisesRegex(oracle.PaletteError,'paint role'):
            oracle.validate_palette_marker(forged,4)
        wrong_pixels = marker(4)
        with self.assertRaises(oracle.PaletteError):
            oracle.inspect_palette_pixels(SyntheticImage(wrong_pixels),m)

    def test_input_trace_integrity(self):
        self.reject_mutations([
            lambda m:m.pop('inputTrace'),
            lambda m:m['inputTrace'].update(revision=99),
            lambda m:m['inputTrace'].update(throughSequence=2),
            lambda m:m['inputTrace']['events'][0].update(dispatched=True),
            lambda m:m['inputTrace']['events'][0].update(sequence=0),
            lambda m:m['inputTrace']['events'][0].update(afterDispatch=1),
            lambda m:m['inputTrace']['events'][0].update(beforeDispatch=1),
            lambda m:m['inputTrace']['events'][0].update(consumed=1),
            lambda m:m['inputTrace']['events'][0].update(kind='move'),
        ])
        m = marker(1)
        event = m['inputTrace']['events'][1]
        event.update(kind='move',dispatched=True,afterDispatch=2,x=20,y=40)
        oracle.validate_palette_marker(m,1)
        for field,value in (('dispatched',False),('x',float('nan')),('sequence',1),('afterDispatch',3)):
            forged = copy.deepcopy(m)
            forged['inputTrace']['events'][1][field] = value
            with self.assertRaises(oracle.PaletteError): oracle.validate_palette_marker(forged,1)
        frames = [marker(p) for p in range(6)]
        frames[3]['inputTrace']['events'][0]['consumed'] = True
        with self.assertRaisesRegex(oracle.PaletteError,'history'):
            oracle.validate_palette_sequence(frames)

    def test_all_ten_roles_and_gate_precedence(self):
        tables = {
            'light':((130,146,164),(35,110,210),(184,190,198),(245,248,252),(226,237,250),(206,224,245),(232,237,244),(238,240,243),(25,43,62),(120,128,139)),
            'dark':((102,126,150),(98,170,255),(100,106,114),(42,71,101),(48,91,137),(35,77,119),(55,70,88),(47,52,60),(242,246,250),(166,171,178))}
        for token,colors in tables.items():
            for bits in range(32):
                hover,focus,press,enabled,load = (bool(bits & (1 << i)) for i in range(5))
                expected = (colors[2 if not enabled else 1 if focus else 0],
                            colors[7 if not enabled else 6 if load else 5 if press else 4 if hover else 3],
                            colors[8 if enabled else 9])
                self.assertEqual(oracle.expected_colors(token,hovered=hover,focused=focus,pressed=press,enabled=enabled,loading=load),expected)
        state = dict(hovered=True,focused=True,pressed=True,enabled=False,loading=True)
        self.assertEqual(oracle.expected_colors('none',**state),oracle.expected_colors('dark',**state))

    def test_forged_missing_unsupported_state_rejected(self):
        mutations = [lambda m:m.pop('enabled'),lambda m:m['palette'].pop('hovered'),
            lambda m:m['palette'].update(hovered=1),lambda m:m.update(enabled=1),
            lambda m:m.update(pressed=True),lambda m:m.update(loading=True),
            lambda m:m.update(enabled=False),lambda m:m.update(focused=True),
            lambda m:m['palette'].update(token='dark'),lambda m:m['palette'].update(token=None),
            lambda m:m['palette'].update(toggleToken='dark'),
            lambda m:m['palette'].update(toggleEnabled=False),
            lambda m:m['palette'].update(toggleLoading=True),
            lambda m:m['palette'].update(toggleEnabled=1),
            lambda m:m['palette'].pop('toggleToken'),
            lambda m:m['palette'].update(revision=False),lambda m:m['palette'].update(extra='unsupported'),
            lambda m:m['palette'].update(hovered=True,toggleHovered=True),
            lambda m:m['palette'].update(actionKeys=['increment']),lambda m:m.update(count=True),
            lambda m:m.update(fixture='spacing'),lambda m:m.update(phase=True)]
        self.reject_mutations(mutations)

    def reject_mutations(self,mutations):
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                m = marker(); mutate(m)
                with self.assertRaises(oracle.PaletteError): oracle.validate_palette_marker(m,0)

    def test_forged_hover_not_inferred_from_rgb(self):
        m = marker(); m['palette']['hovered'] = True
        with self.assertRaisesRegex(oracle.PaletteError,'paint role'): oracle.validate_palette_marker(m,0)

    def test_scene_color_geometry_and_unsupported_data(self):
        self.reject_mutations([
            lambda m:m['scene']['items'][3]['color'].update(alpha=254),
            lambda m:m['scene']['items'][4]['color'].update(red=35),
            lambda m:m['scene']['items'][5]['color'].update(red=0),
            lambda m:m['scene']['items'][3].update(id=99),
            lambda m:m['scene']['items'][4]['bounds'].update(x=6),
            lambda m:m['scene']['items'][5]['bounds'].update(width=24),
            lambda m:m['scene']['items'][5].update(kind='text'),
            lambda m:m['scene']['items'][5].update(text='Wrong'),
            lambda m:m['scene']['items'][5].pop('text_origin'),
            lambda m:m['scene']['items'][3]['transform'].update(tx=1),
            lambda m:m['scene']['items'][3].update(opacity=.5),
            lambda m:m['scene']['items'][3].update(shader='unknown'),
            lambda m:m['scene']['items'][0]['color'].update(red=0),
            lambda m:m['scene']['items'][3].update(clip_chain_id=1),
            lambda m:m['scene'].update(resources=[{}]),lambda m:m['scene'].update(schema_version=2),
            lambda m:m['scene']['items'].append(copy.deepcopy(m['scene']['items'][3])),
            lambda m:m['scene']['items'].reverse(),lambda m:m['scene'].update(scale=2),
            lambda m:m['frame'].update(width=500),lambda m:m['frame'].update(path=''),
            lambda m:m['root'].update(width=float('nan')),lambda m:m.update(scale=True),
            lambda m:m['palette'].update(buttonId=19),
        ])

    def test_stale_frame_revision_source_scene_and_geometry_sequence(self):
        for kind in ('path','revision','bounds','id','wrong_phase_scene'):
            with self.subTest(kind=kind):
                frames = [marker(p) for p in range(6)]
                if kind == 'path': frames[1]['frame']['path'] = frames[0]['frame']['path']
                if kind == 'revision': frames[1]['palette']['revision'] = 1
                if kind == 'bounds': frames[1]['heading']['x'] += 1
                if kind == 'id': frames[1]['scene']['items'][0]['id'] = 99
                if kind == 'wrong_phase_scene': frames[2]['scene'] = frames[0]['scene']
                with self.assertRaises(oracle.PaletteError): oracle.validate_palette_sequence(frames)

    def test_wrong_source_pixels_dimensions_solid_and_missing_glyph(self):
        m = marker(2)
        with self.assertRaises(oracle.PaletteError): oracle.inspect_palette_pixels(SyntheticImage(marker(0)),m)
        image = SyntheticImage(m); image.width = 119
        with self.assertRaises(oracle.PaletteError): oracle.inspect_palette_pixels(image,m)
        image = SyntheticImage(m); image.data[30][29] = (0,0,0)
        with self.assertRaises(oracle.PaletteError): oracle.inspect_palette_pixels(image,m)
        image = SyntheticImage(m)
        for y in range(40,50):
            for x in range(15,40): image.data[y][x] = (245,248,252)
        with self.assertRaisesRegex(oracle.PaletteError,'glyph'): oracle.inspect_palette_pixels(image,m)

    def test_portable_pressed_and_gated_scene_preserves_focus_inset(self):
        for token in ('light','dark','none'):
            for enabled,loading,pressed in ((True,False,True),(True,True,True),(False,True,True)):
                state = dict(hovered=True,focused=True,pressed=pressed,enabled=enabled,loading=loading)
                colors = oracle.expected_colors(token,**state)
                items = [paint(11,'quad',box(4,30,50,30),colors[0]),paint(12,'quad',box(6,32,46,26),colors[1]),paint(13,'text_run',box(15,40,25,10),colors[2],'Increment')]
                oracle.validate_button_scene(items,10,box(4,30,50,30),box(15,40,25,10),'Increment',token,**state)
                items[1]['bounds'] = box(5,31,48,28)
                with self.assertRaises(oracle.PaletteError):
                    oracle.validate_button_scene(items,10,box(4,30,50,30),box(15,40,25,10),'Increment',token,**state)


if __name__ == '__main__': unittest.main()
