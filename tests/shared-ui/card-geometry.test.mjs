import test from 'node:test';
import assert from 'node:assert/strict';
import {checkCardGeometry} from './card.mjs';
const valid = () => ({kind:'DIV',tabIndex:-1,role:null,border:Array(4).fill('1px'),padding:Array(4).fill('16px'),gap:'12px',radius:'0px',x:24,y:24,width:100,height:86,children:[{x:41,y:41,width:66,height:20},{x:41,y:73,width:66,height:20}]});
test('Card geometry oracle checks every inset gap and noninteraction', () => {
  checkCardGeometry(valid());
  for (const mutate of [c => c.border[0]='0px', c => c.padding[2]='15px', c => c.gap='10px',
    c => c.tabIndex=0, c => c.role='button', c => c.children[0].x+=3,
    c => c.children[1].y+=3, c => c.width+=3, c => c.height+=3]) {
    const card=valid(); mutate(card); assert.throws(() => checkCardGeometry(card), assert.AssertionError);
  }
});
