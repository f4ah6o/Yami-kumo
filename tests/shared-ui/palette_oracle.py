"""Bounded palette consumer oracle; inert, with no host/capture side effects.

State comes only from the accepted CounterFrame marker, never from RGB. The
caller must read the PPM named by that marker and bind clean source/binary/log
provenance (native_driver does so). Synthetic inputs do not qualify a host.
This module does not replace the older settled-frame oracles.
"""
from __future__ import annotations
import math


class PaletteError(ValueError):
    pass


ROLES = ('normal_border', 'focused_border', 'disabled_border', 'normal_fill',
         'hovered_fill', 'pressed_fill', 'loading_fill', 'disabled_fill',
         'enabled_foreground', 'disabled_foreground')
PALETTES = {
    'light': dict(zip(ROLES, ((130,146,164),(35,110,210),(184,190,198),
        (245,248,252),(226,237,250),(206,224,245),(232,237,244),(238,240,243),
        (25,43,62),(120,128,139)))),
    'dark': dict(zip(ROLES, ((102,126,150),(98,170,255),(100,106,114),
        (42,71,101),(48,91,137),(35,77,119),(55,70,88),(47,52,60),
        (242,246,250),(166,171,178)))),
}
TOKENS = ('none', 'none', 'light', 'light', 'dark', 'none')
COUNTS = (0,1,1,2,2,2)
ACTIONS = ('increment','palette-toggle','increment','palette-toggle','palette-toggle')
PALETTE_KEYS = {'token','toggleToken','toggleEnabled','toggleLoading','hovered','toggleHovered','togglePressed','toggleFocused',
                'toggle','toggleLabel','buttonId','toggleId','revision','actionKeys'}
IDENTITY = dict(a=1,b=0,c=0,d=1,tx=0,ty=0)


def require(test, message):
    if not test:
        raise PaletteError(message)


def number(value):
    require(type(value) in (int,float) and math.isfinite(value), 'invalid finite number')
    return value


def rect(value):
    require(isinstance(value,dict) and set(value) == {'x','y','width','height'}, 'invalid bounds schema')
    result = tuple(number(value[k]) for k in ('x','y','width','height'))
    require(result[2] > 0 and result[3] > 0, 'empty bounds')
    return result


def inside(inner, outer):
    x,y,w,h = inner
    a,b,c,d = outer
    require(x >= a and y >= b and x+w <= a+c and y+h <= b+d, 'bounds outside container')


def expected_colors(token, *, hovered, focused, pressed, enabled, loading):
    """All ten frozen roles, including portable-only gated/held states."""
    require(type(token) is str and token in ('none','light','dark'), 'unsupported token')
    require(all(type(x) is bool for x in (hovered,focused,pressed,enabled,loading)), 'state must be explicit booleans')
    colors = PALETTES['dark' if token == 'none' else token]
    border = 'disabled_border' if not enabled else 'focused_border' if focused else 'normal_border'
    fill = ('disabled_fill' if not enabled else 'loading_fill' if loading else
            'pressed_fill' if pressed else 'hovered_fill' if hovered else 'normal_fill')
    foreground = 'enabled_foreground' if enabled else 'disabled_foreground'
    return tuple(colors[key] for key in (border,fill,foreground))


def _color(item, expected):
    value = item.get('color')
    require(isinstance(value,dict) and set(value) == {'red','green','blue','alpha'}, 'invalid color schema')
    require(all(type(v) is int for v in value.values()), 'color channels must be integers')
    require(tuple(value[k] for k in ('red','green','blue','alpha')) == (*expected,255), 'wrong paint role or alpha')


def validate_button_scene(items, binding_id, bounds, label_bounds, label, token, **state):
    """Pure scene/state check; does not assert that this state ran on a host."""
    require(type(binding_id) is int and binding_id > 0, 'invalid binding ID')
    colors = expected_colors(token, **state)
    b, lb = rect(bounds), rect(label_bounds)
    inside(lb,b)
    selected = [item for item in items if item.get('id') in (binding_id+1,binding_id+2,binding_id+3)]
    require([item.get('id') for item in selected] == [binding_id+1,binding_id+2,binding_id+3], 'missing, duplicated or reordered Button paint IDs')
    inset = 2 if state['focused'] else 1
    require(b[2] > 2*inset and b[3] > 2*inset, 'Button too small for focus inset')
    inside(lb,(b[0]+inset,b[1]+inset,b[2]-2*inset,b[3]-2*inset))
    expected_bounds = (b,(b[0]+inset,b[1]+inset,b[2]-2*inset,b[3]-2*inset),lb)
    for index,(item,color,geometry) in enumerate(zip(selected,colors,expected_bounds)):
        keys = {'kind','id','bounds','color','transform','opacity','clip_chain_id'}
        if index == 2:
            keys |= {'text','font_size','text_origin'}
        require(set(item) == keys, 'unsupported Button scene fields')
        require(item.get('kind') == ('text_run' if index == 2 else 'quad'), 'unsupported Button paint kind')
        require(rect(item.get('bounds')) == geometry, 'Button paint geometry mismatch')
        _color(item,color)
        transform = item.get('transform')
        require(isinstance(transform,dict) and set(transform) == set(IDENTITY) and
                all(number(transform[k]) == v for k,v in IDENTITY.items()), 'unsupported transform')
        require(number(item.get('opacity')) == 1 and item.get('clip_chain_id', 'missing') is None, 'unsupported opacity/clip')
    text = selected[2]
    require(text.get('text') == label and number(text.get('font_size')) > 0, 'wrong Button label/font')
    origin = text.get('text_origin')
    require(isinstance(origin,dict) and set(origin) == {'x','y'}, 'missing measured text origin')
    number(origin['x']); number(origin['y'])
    return colors


def _buttons(marker):
    p = marker['palette']
    shared = dict(enabled=marker['enabled'],loading=marker['loading'])
    return ((p['buttonId'],marker['button'],marker['buttonLabel'],'Increment',
             dict(shared,hovered=p['hovered'],focused=marker['focused'],pressed=marker['pressed'])),
            (p['toggleId'],p['toggle'],p['toggleLabel'],'Palette',
             dict(enabled=p['toggleEnabled'],loading=p['toggleLoading'],hovered=p['toggleHovered'],focused=p['toggleFocused'],pressed=p['togglePressed'])))


def validate_input_trace(marker):
    trace = marker.get('inputTrace')
    require(isinstance(trace,dict) and set(trace) == {'revision','throughSequence','events'}, 'missing input trace')
    require(type(trace['revision']) is int and trace['revision'] == marker['palette']['revision'], 'input trace revision mismatch')
    require(type(trace['throughSequence']) is int and trace['throughSequence'] >= 0, 'invalid trace boundary')
    events = trace['events']
    require(isinstance(events,list) and len(events) <= 4096, 'unbounded input trace')
    previous = 0
    last_dispatch = 0
    for event in events:
        require(isinstance(event,dict), 'invalid trace event')
        kind = event.get('kind')
        require(kind in ('move','primary-down','primary-up','other-input','focus','other-window'), 'invalid trace kind')
        fields = {'sequence','scale','consumed','dispatched','beforeDispatch','afterDispatch','kind'}
        if kind in ('move','primary-down','primary-up'): fields |= {'x','y'}
        if kind == 'focus': fields |= {'focused'}
        require(set(event) == fields, 'invalid trace event fields')
        require(type(event['sequence']) is int and previous < event['sequence'] <= trace['throughSequence'], 'trace sequence mismatch')
        previous = event['sequence']
        require(number(event['scale']) > 0, 'invalid trace scale')
        require(type(event['consumed']) is bool and type(event['dispatched']) is bool, 'invalid trace dispatch flags')
        before, after = event['beforeDispatch'], event['afterDispatch']
        require(type(before) is int and type(after) is int and before == last_dispatch and after in (before,event['sequence']), 'invalid dispatch witness')
        require(event['dispatched'] == (after == event['sequence'] and after != before), 'dispatch witness mismatch')
        last_dispatch = after
        if kind in ('focus','other-window'): require(not event['dispatched'], 'non-input dispatched')
        if kind == 'focus': require(type(event['focused']) is bool, 'invalid trace focus')
        if 'x' in event: number(event['x']); number(event['y'])
    require(previous == trace['throughSequence'], 'trace boundary does not match final event')


def validate_palette_marker(marker, phase):
    require(type(phase) is int and 0 <= phase < 6, 'unsupported palette phase')
    require(isinstance(marker,dict) and marker.get('fixture') == 'palette' and
            type(marker.get('phase')) is int and marker['phase'] == phase, 'wrong fixture/phase')
    p = marker.get('palette')
    require(isinstance(p,dict) and set(p) == PALETTE_KEYS, 'missing or unsupported frame state')
    require(p['token'] == TOKENS[phase] and p['toggleToken'] == TOKENS[phase], 'token does not match accepted phase')
    for key in ('count','value','releases'):
        require(type(marker.get(key)) is int and marker[key] == (phase if key == 'releases' else COUNTS[phase]), 'wrong phase count/releases')
    require(marker.get('actions') == ['Activate']*phase and p['actionKeys'] == list(ACTIONS[:phase]), 'wrong action trace')
    require(type(p['revision']) is int and p['revision'] > 0, 'missing accepted frame revision')
    validate_input_trace(marker)
    require(all(type(marker.get(k)) is bool for k in ('enabled','loading','pressed','focused')), 'missing top-level state')
    require(all(type(p[k]) is bool for k in ('hovered','toggleHovered','togglePressed','toggleFocused','toggleEnabled','toggleLoading')), 'missing nested state')
    require(p['toggleEnabled'] and not p['toggleLoading'] and marker['enabled'] and not marker['loading'] and not marker['pressed'] and not p['togglePressed'], 'actual fixture is enabled nonloading and settled')
    require(marker['focused'] == (phase in (1,3)) and p['toggleFocused'] == (phase in (2,4,5)), 'focus differs from pointer phase')
    # Routed primary clicks can retain another Button's hover until delivered motion.
    require(type(p['buttonId']) is int and type(p['toggleId']) is int and abs(p['buttonId']-p['toggleId']) >= 4, 'overlapping Button IDs')
    root = rect(marker.get('root'))
    require(root[:2] == (0,0), 'root must be frame local')
    scale = number(marker.get('scale'))
    require(scale > 0, 'invalid scale')
    scene = marker.get('scene')
    require(isinstance(scene,dict) and type(scene.get('schema_version')) is int and scene['schema_version'] == 1, 'unsupported scene schema')
    require(scene.get('resources') == [] and scene.get('clip_chains') == [], 'unsupported scene resources/clips')
    require(rect(scene.get('viewport')) == root and number(scene.get('scale')) == scale, 'scene/frame geometry mismatch')
    items = scene.get('items')
    require(isinstance(items,list) and len(items) == 9 and all(isinstance(i,dict) for i in items), 'unsupported scene items')
    background = items[0]
    require(background.get('kind') == 'quad' and background.get('id') == 1 and rect(background.get('bounds')) == root, 'wrong viewport background')
    _color(background,(245,247,250))
    require(background.get('transform') == IDENTITY and background.get('opacity') == 1 and background.get('clip_chain_id', 'missing') is None, 'unsupported background paint')
    ids = [i.get('id') for i in items]
    require(all(type(i) is int and i > 0 for i in ids) and len(set(ids)) == len(ids), 'duplicate/invalid scene IDs')
    for label in ('Shared palette',f'Count: {COUNTS[phase]}'):
        require(sum(i.get('kind') == 'text_run' and i.get('text') == label for i in items) == 1, 'missing heading/counter text')
    for bid,b,lb,label,state in _buttons(marker):
        inside(rect(b),root)
        validate_button_scene(items,bid,b,lb,label,p['token'] if bid == p['buttonId'] else p['toggleToken'],**state)
    a,b = rect(marker['button']),rect(p['toggle'])
    require(a[0]+a[2] <= b[0] or b[0]+b[2] <= a[0] or a[1]+a[3] <= b[1] or b[1]+b[3] <= a[1], 'Button bounds overlap')
    frame = marker.get('frame')
    require(isinstance(frame,dict) and isinstance(frame.get('path'),str) and bool(frame['path']), 'missing completed frame path')
    require(all(type(frame.get(k)) is int and 0 < frame[k] <= 8192 for k in ('width','height')), 'invalid or unbounded capture dimensions')
    require(number(frame.get('scale')) == scale and abs(frame['width']-root[2]*scale) <= 1 and abs(frame['height']-root[3]*scale) <= 1, 'capture/frame geometry mismatch')


def validate_palette_sequence(markers):
    require(isinstance(markers,list) and len(markers) == 6, 'all six palette phases required')
    paths = set()
    for phase, marker in enumerate(markers):
        validate_palette_marker(marker,phase)
        path = marker['frame']['path']
        require(path not in paths, 'stale reused capture path')
        paths.add(path)
        if phase:
            prior = markers[phase-1]['inputTrace']['events']
            require(marker['inputTrace']['events'][:len(prior)] == prior, 'input trace history changed')
            require(marker['inputTrace']['throughSequence'] > markers[phase-1]['inputTrace']['throughSequence'], 'input trace did not advance')
            require(marker['palette']['revision'] > markers[phase-1]['palette']['revision'], 'stale accepted frame revision')
        for key in ('root','scale','button','buttonLabel','heading'):
            require(marker.get(key) == markers[0].get(key), 'palette changed fixed geometry')
        for key in ('buttonId','toggleId','toggle','toggleLabel'):
            require(marker['palette'][key] == markers[0]['palette'][key], 'palette replaced geometry/binding ID')
        # Count glyph width can change; paint IDs and Button text metrics cannot.
        require([i['id'] for i in marker['scene']['items']] == [i['id'] for i in markers[0]['scene']['items']], 'palette replaced scene IDs')


def inspect_palette_pixels(image, marker):
    """Check completed PPM solid paint and visible glyph contrast, not font parity.

    Solid samples tolerate 2 RGB units. Glyph visibility requires >=3 pixels at
    least 12 units from fill, nearer the declared foreground; antialiasing is
    allowed and no particular glyph raster or font metric is mandated.
    """
    validate_palette_marker(marker,marker.get('phase'))
    require((image.width,image.height) == (marker['frame']['width'],marker['frame']['height']), 'PPM dimensions mismatch')
    scale = marker['scale']
    observations = []
    for bid,bounds,label_bounds,label,state in _buttons(marker):
        border,fill,fg = expected_colors(marker['palette']['token'] if bid == marker['palette']['buttonId'] else marker['palette']['toggleToken'],**state)
        x,y,w,h = rect(bounds)
        inset = 2 if state['focused'] else 1
        points = ((x+w/2,y+.5),(x+w-.5,y+h/2),(x+w/2,y+h-.5),(x+.5,y+h/2),(x+inset+.5,y+inset+.5))
        samples = []
        for (px,py),color in zip(points,(border,border,border,border,fill)):
            actual = tuple(image.pixel(int(px*scale),int(py*scale)))
            require(len(actual) == 3 and all(abs(a-b) <= 2 for a,b in zip(actual,color)), 'PPM solid paint mismatch')
            samples.append(list(actual))
        lx,ly,lw,lh = rect(label_bounds)
        visible = 0
        for py in range(max(0,math.ceil(ly*scale)),min(image.height,math.floor((ly+lh)*scale))):
            for px in range(max(0,math.ceil(lx*scale)),min(image.width,math.floor((lx+lw)*scale))):
                color = image.pixel(px,py)
                delta = max(abs(a-b) for a,b in zip(color,fill))
                # Pixel must progress toward foreground on every varying channel.
                if delta >= 12 and all(min(f,b)-2 <= c <= max(f,b)+2 for c,f,b in zip(color,fg,fill)):
                    visible += 1
        require(visible >= 3, 'PPM Button label has no visible foreground glyphs')
        observations.append({'bindingId':bid,'label':label,'solidSamples':samples,'visibleGlyphPixels':visible})
    return observations
