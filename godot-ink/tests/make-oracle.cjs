// Run from the port root. The shipped web engine is a read-only oracle.
const fs=require('fs'), path=require('path');
const original=path.resolve('..','道友请留步-v15-洞府主界面版-20260927');
const E=require(path.join(original,'js/engine.js')),D=require(path.join(original,'js/data.js'));
const clone=x=>JSON.parse(JSON.stringify(x));
const suites=[];
function suite(name,s,actions){
 const initial=clone(s), steps=[];
 for(const action of actions){let ok=true;try{s=E.dispatch(s,action).state;}catch{ok=false;}
  steps.push({action,ok,state:clone(s)});
 }suites.push({name,initial,steps});return s;
}
function battle(seed=22){let s=E.create(seed);s=E.dispatch(s,{type:'newRun'}).state;return E.dispatch(s,{type:'enterNode',id:'f1'}).state;}
for(let seed=1;seed<=40;seed++)suite('board-seed-'+seed,E.create(seed),[{type:'newRun'},{type:'enterNode',id:'f1'}]);
suite('deck-guards',E.create(9),[{type:'deckRemove',slot:0},{type:'newRun'},{type:'deckEquip',slot:0,id:'ward'},{type:'deckEquip',slot:0,id:'thunder'},{type:'deckEquip',slot:0,id:'step'},{type:'newRun'},{type:'deckRemove',slot:0},{type:'deckEquip',slot:0,id:'sword'},{type:'enterNode',id:'boss'},{type:'enterNode',id:'f1'},{type:'equip',id:'jade'},{type:'sell',id:'cloth'}]);
for(const c of D.cards){
 let s=battle();s.profile.collection[c.id]=1;s.profile.hp=30;s.battle.hand[0].cardId=c.id;s.battle.mana=7;s.battle.enemy.shield=20;
 suite('repeat-'+c.id,s,Array.from({length:9},()=>({type:'card',uid:s.battle.hand[0].uid})));
 s=battle();s.battle.hand[0].cardId=c.id;s.battle.mana=7;s.profile.hp=100;
 suite('full-health-'+c.id,s,[{type:'card',uid:s.battle.hand[0].uid}]);
}
for(const id of ['f1','elite','boss']){
 let s=E.create(81);s=E.dispatch(s,{type:'newRun'}).state;s.run.nodes[id]='available';s=E.dispatch(s,{type:'enterNode',id}).state;
 s.profile.legacy.hp=10000;s.profile.hp=10000;s.battle.shield=70;
 suite('enemy-pattern-'+id,s,Array.from({length:12},()=>({type:'endTurn'})));
 if(id==='boss'){
  s.battle.enemy.hp=Math.floor(s.battle.enemy.maxHp/2)+1;s.battle.mana=7;
  suite('enrage-lock',s,[{type:'endTurn'},{type:'card',uid:s.battle.hand[0].uid},{type:'endTurn'},{type:'endTurn'},{type:'endTurn'}]);
 }
}
for(const kind of ['defeat','revive']){
 let s=battle();s.profile.hp=1;s.battle.shield=0;if(kind==='revive')s.run.treasures=['revive'];
 suite(kind,s,[{type:'endTurn'},{type:'endTurn'}]);
}
for(const count of [0,1,2,7]){
 let s=battle(933);s.battle.enemy.hp=1;s.battle.mana=7;
 for(const c of D.cards)s.profile.collection[c.id]=1;
 for(const c of D.cards.filter(c=>!s.profile.deck.includes(c.id)).slice(0,count))s.profile.collection[c.id]=0;
 const first={type:'card',uid:s.battle.hand[0].uid};const win=E.dispatch(s,first).state;
 suite('reward-choices-'+count,s,[first,{type:'reward',id:win.run.pendingReward.choices[0]||''}]);
}
let s=E.create(44);s.profile.coins=10000;
suite('economy',s,[{type:'equip',id:'jade'},{type:'claimTask',id:'equip'},{type:'claimTask',id:'equip'},...Array.from({length:10},()=>({type:'cultivate'})),{type:'claimTask',id:'cultivate'},{type:'use',id:'spring_pill'},{type:'use',id:'cloud_talisman'},{type:'use',id:'golden_gourd'},{type:'sell',id:'cloth'},{type:'unequip',id:'armor'},{type:'sell',id:'cloth'},{type:'sell',id:'spirit_stone'},{type:'buyItem',id:'spring_pill'},{type:'buyTreasure',id:'ice'},{type:'newRun'},...D.treasures.map(t=>({type:'buyTreasure',id:t.id})),{type:'buyTreasure',id:'ice'},{type:'enterNode',id:'f1'},{type:'use',id:'cloud_talisman'},{type:'use',id:'spring_pill'},{type:'abandon'},{type:'clearResult'}]);
for(let seed=500;seed<506;seed++){
 s=E.create(seed);s.profile.legacy.hp=20000;s.profile.hp=20100;s.profile.coins=10000;
 for(const c of D.cards)s.profile.collection[c.id]=1;
 s.profile.deck=['sword','spiritArray','step'];
 const initial=clone(s),steps=[];
 for(let i=0;i<2200;i++){
  let action;
  if(s.lastResult){action={type:'clearResult'};}
  else if(!s.run){action={type:'newRun'};}
  else if(s.run.pendingReward){action={type:'reward',id:s.run.pendingReward.choices[0]||''};}
  else if(!s.battle){const nodes=D.nodes.filter(n=>s.run.nodes[n.id]==='available');action={type:'enterNode',id:nodes[(seed+i)%nodes.length].id};}
  else if(s.battle.mana>=3&&i%4===0){action={type:'card',uid:s.battle.hand[0].uid};}
  else if(s.battle.steps){const [a,b]=E.possibleMove(s.battle.board);action={type:'swap',a,b};}
  else action={type:'endTurn'};
  s=E.dispatch(s,action).state;steps.push({action,ok:true,state:clone(s)});
  if(s.profile.records.clears>=1)break;
 }
 if(s.profile.records.clears<1)throw new Error('Full four-chapter regression did not finish');
 suites.push({name:'playthrough-'+seed,initial,steps});
}
fs.writeFileSync('tests/oracle.json',JSON.stringify(suites));
console.log(`${suites.length} suites; ${suites.reduce((n,s)=>n+s.steps.length,0)} state checkpoints`);
