// Генератор макетов 1920×1080. Экран выбирается через #hash (имя PNG без расширения).
// Все размеры — из ../tokens.json. Тексты — пример для русской локали.

const ICONS = {
  play:'<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.5-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5z"/>',
  plus:'<path d="M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z"/>',
  check:'<path d="M9.5 16.2 5.3 12l-1.4 1.4 5.6 5.6L20.1 8.4 18.7 7z"/>',
  film:'<path d="M4 4h16v16H4zm2 2v2h2V6zm10 0v2h2V6zM6 10v4h2v-4zm10 0v4h2v-4zM6 16v2h2v-2zm10 0v2h2v-2zM10 6v12h4V6z"/>',
  more:'<circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/>',
  search:'<path d="M10 3a7 7 0 0 1 5.6 11.2l5.1 5.1-1.4 1.4-5.1-5.1A7 7 0 1 1 10 3zm0 2a5 5 0 1 0 0 10 5 5 0 0 0 0-10z"/>',
  home:'<path d="M12 3 3 10.5V21h6v-6h6v6h6V10.5z"/>',
  movie:'<path d="M3 5h18v14H3zm2 2v10h14V7zm4 2 6 3-6 3z"/>',
  tv:'<path d="M3 6h18v12H3zm2 2v8h14V8zm3 12h8v2H8z"/>',
  music:'<path d="M9 4h11v12.5a3.5 3.5 0 1 1-2-3.16V8h-7v10.5a3.5 3.5 0 1 1-2-3.16z"/>',
  list:'<path d="M6 3h12v18l-6-4-6 4z"/>',
  gear:'<path d="M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8zm-1-6h2l.5 2.6 2 .9 2.2-1.5 1.4 1.4-1.5 2.2.9 2 2.6.5v2l-2.6.5-.9 2 1.5 2.2-1.4 1.4-2.2-1.5-2 .9L13 22h-2l-.5-2.6-2-.9-2.2 1.5-1.4-1.4 1.5-2.2-.9-2L2 13v-2l2.6-.5.9-2L4 6.3 5.4 4.9l2.2 1.5 2-.9z"/>',
  user:'<path d="M12 3a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9zm0 11c4.4 0 8 2.2 8 5v2H4v-2c0-2.8 3.6-5 8-5z"/>',
  sub:'<path d="M3 5h18v14H3zm3 7v2h5v-2zm7 0v2h5v-2zm-7 3v2h9v-2z"/>',
  speaker:'<path d="M4 9h4l5-4v14l-5-4H4zm12 .5a4 4 0 0 1 0 5l1.4 1.4a6 6 0 0 0 0-7.8z"/>',
  mic:'<path d="M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zm-7 9h2a5 5 0 0 0 10 0h2a7 7 0 0 1-6 6.9V21h-2v-2.1A7 7 0 0 1 5 12z"/>',
  back:'<path d="M9 5h11v14H9l-6-7zm3 4 2 2-2 2 1.4 1.4 2-2 2 2L18.8 13l-2-2 2-2-1.4-1.4-2 2-2-2z"/>',
  space:'<path d="M4 11h2v3h12v-3h2v5H4z"/>',
  history:'<path d="M13 3a9 9 0 1 1-8.5 12h2.1A7 7 0 1 0 6 9.3L8.5 12H2V5.5l2.6 2.6A9 9 0 0 1 13 3zm-1 5h2v4.4l3 1.8-1 1.7-4-2.4z"/>',
  sort:'<path d="M7 4l4 4H8v8H6V8H3zm10 16-4-4h3V8h2v8h3z"/>',
  filter:'<path d="M3 5h18l-7 8v6l-4 2v-8z"/>',
  cloudOff:'<path d="M3.3 2 22 20.7 20.7 22l-2-2H7a5 5 0 0 1-1.3-9.8L2 3.3zM12 5a7 7 0 0 1 6.9 5.9A4.5 4.5 0 0 1 21 18.6L8.5 6.1A7 7 0 0 1 12 5z"/>',
  bookmark:'<path d="M6 3h12v18l-6-4-6 4zm2 2v12.2l4-2.7 4 2.7V5z"/>',
  noresult:'<path d="M10 3a7 7 0 0 1 5.6 11.2l5.1 5.1-1.4 1.4-5.1-5.1A7 7 0 1 1 10 3zm-2.1 4.5L6.5 8.9 8.6 11l-2.1 2.1 1.4 1.4L10 12.4l2.1 2.1 1.4-1.4-2.1-2.1 2.1-2.1-1.4-1.4L10 9.6z"/>',
  refresh:'<path d="M12 4a8 8 0 0 1 7.4 5H22l-3.5 4L15 9h2.2A6 6 0 1 0 18 13h2a8 8 0 1 1-8-9z"/>',
  server:'<path d="M4 4h16v6H4zm0 10h16v6H4zm3-8v2h2V6zm0 10v2h2v-2z"/>',
};
const ico = (n, cls='') => `<svg class="svg-ico ${cls}" viewBox="0 0 24 24">${ICONS[n]}</svg>`;

// ---------- данные ----------
const M = {
  dune:{t:'Дюна: Часть вторая',y:2024,h:32},
  brat:{t:'Брат',y:1997,h:200},
  vrungel:{t:'Приключения капитана Врунгеля: возвращение',y:2025,h:205,short:'Капитан Врунгель'},
  stalker:{t:'Сталкер',y:1979,h:90},
  solaris:{t:'Солярис',y:1972,h:220},
  oppen:{t:'Оппенгеймер',y:2023,h:20},
  levi:{t:'Левиафан',y:2014,h:195},
  irony:{t:'Ирония судьбы, или С лёгким паром!',y:1976,h:350,short:'Ирония судьбы'},
  moscow:{t:'Москва слезам не верит',y:1979,h:330},
  cheb:{t:'Чебурашка',y:2023,h:28},
  t34:{t:'Т-34',y:2018,h:60},
  leg17:{t:'Легенда №17',y:2013,h:0},
  up:{t:'Движение вверх',y:2017,h:215},
  ruka:{t:'Бриллиантовая рука',y:1968,h:45},
  master:{t:'Мастер и Маргарита',y:2024,h:345},
  inter:{t:'Интерстеллар',y:2014,h:210},
  incep:{t:'Начало',y:2010,h:225},
  blade:{t:'Бегущий по лезвию 2049',y:2017,h:15},
  sib:{t:'Сибирский цирюльник',y:1998,h:38},
  ex:{t:'Экипаж',y:2016,h:185},
  vyzov:{t:'Вызов',y:2023,h:235},
  ice:{t:'Лёд',y:2018,h:190},
  kholop:{t:'Холоп',y:2019,h:10},
  duna1:{t:'Дюна',y:2021,h:36},
  arrival:{t:'Прибытие',y:2016,h:170},
  sicario:{t:'Убийца',y:2015,h:30},
  prisoners:{t:'Пленницы',y:2013,h:180},
};
const S = {
  dark:{t:'Тьма',y:'2017–2020',seasons:3,h:165},
  slovo:{t:'Слово пацана. Кровь на асфальте',y:2023,seasons:1,h:12,short:'Слово пацана'},
  method:{t:'Метод',y:'2015–2021',seasons:2,h:0},
  epid:{t:'Эпидемия',y:'2019–2022',seasons:2,h:180},
  chern:{t:'Чернобыль',y:2019,seasons:1,h:75},
  sherlock:{t:'Шерлок',y:'2010–2017',seasons:4,h:215},
  detective:{t:'Настоящий детектив',y:'2014–2024',seasons:4,h:25},
  horses:{t:'Медленные лошади',y:'2022–2024',seasons:4,h:140},
  trigger:{t:'Триггер',y:'2018–2023',seasons:2,h:350},
  kitchen:{t:'Кухня',y:'2012–2016',seasons:6,h:40},
};
const seasonsWord = n => n===1?'1 сезон':(n<5?`${n} сезона`:`${n} сезонов`);

// ---------- арт (заглушки обложек; в реальности — постеры с сервера) ----------
function hsl(h,s,l,a=1){return `hsla(${h},${s}%,${l}%,${a})`}
function posterArt(it, w, h, i=0){
  const hue = it.h ?? 200, v = (it.t.length + i) % 4;
  const name = (it.short || it.t);
  const fs = Math.round(w/9.5);
  let shape = '';
  if (v===0) shape = `<div class="abs" style="left:${w*.2}px;top:${h*.18}px;width:${w*.6}px;height:${w*.6}px;border-radius:50%;background:radial-gradient(circle,${hsl(hue+20,70,70,.9)},${hsl(hue,60,45,0)} 70%)"></div>`;
  if (v===1) shape = `<div class="abs" style="left:0;right:0;top:${h*.55}px;height:${h*.45}px;background:linear-gradient(180deg,${hsl(hue,30,8,0)},${hsl(hue,30,6,.9)})"></div><div class="abs" style="left:${w*.38}px;top:${h*.22}px;width:${w*.24}px;height:${h*.42}px;border-radius:${w*.12}px ${w*.12}px 4px 4px;background:${hsl(hue,25,10,.85)}"></div>`;
  if (v===2) shape = `<div class="abs" style="left:-${w*.1}px;right:-${w*.1}px;top:${h*.48}px;height:${h*.7}px;border-radius:50% 50% 0 0;background:${hsl(hue+10,35,18)}"></div>`;
  if (v===3) shape = `<div class="abs" style="left:${w*.12}px;top:${h*.12}px;right:${w*.12}px;bottom:${h*.38}px;border:2px solid ${hsl(hue,60,75,.5)};border-radius:4px"></div>`;
  return `<div style="position:absolute;inset:0;background:linear-gradient(165deg,${hsl(hue,48,42)} 0%,${hsl(hue+15,42,22)} 45%,${hsl(hue+25,40,10)} 100%)"></div>${shape}
    <div class="pa-title ${v===3?'':''}" style="font-size:${fs}px;line-height:${fs*1.12}px">${name}</div>`;
}
function stillArt(hue, w, h, i=0){
  const sky = hsl(hue+((i*23)%40)-20, 30, 34 - (i%3)*6);
  return `<div style="position:absolute;inset:0;background:linear-gradient(180deg,${sky} 0%,${hsl(hue,28,16)} 58%,${hsl(hue+10,30,9)} 100%)"></div>
    <div class="abs" style="left:${(i*97)%w*0.6}px;top:${h*.2}px;width:${w*.22}px;height:${w*.22}px;border-radius:50%;background:radial-gradient(circle,${hsl(hue+30,55,70,.55)},transparent 70%)"></div>
    <div class="abs" style="left:0;right:0;bottom:0;height:${h*.4}px;background:${hsl(hue+5,25,8,.85)};clip-path:polygon(0 40%,${15+i*7}% 10%,${35+i*5}% 55%,${60}% 20%,${80-i*3}% 60%,100% 30%,100% 100%,0 100%)"></div>`;
}
function backdropScene(hue){
  return `<div class="scene" style="background:
    radial-gradient(ellipse 520px 360px at 62% 34%,${hsl(hue+15,60,62,.55)},transparent 70%),
    radial-gradient(ellipse 900px 420px at 40% 105%,${hsl(hue,40,22,.95)},transparent 70%),
    linear-gradient(180deg,${hsl(hue+5,40,30)} 0%,${hsl(hue,35,18)} 55%,${hsl(hue,30,10)} 100%)"></div>
    <div class="scene" style="background:linear-gradient(0deg,${hsl(hue,30,8,.9)} 0%,transparent 35%);clip-path:polygon(0 72%,18% 60%,30% 68%,46% 52%,58% 64%,74% 50%,88% 62%,100% 55%,100% 100%,0 100%)"></div>`;
}

// Фон экрана: подкраска под обложку (tokens.color.bg) + опциональный backdrop.
function tintColors(hue){
  // tint: S ≤ 0.45, L ∈ [0.10;0.18]; верх = lerp(bg, tint, 0.44)
  return { top: hsl(hue,35,11), tint: hsl(hue,32,9), bottom:'#0E0F12' };
}
function screenBg(hue, withBackdrop=true, bdTop=0){
  const c = tintColors(hue);
  let html = `<div class="abs" style="inset:0;background:linear-gradient(180deg,${c.top} 0%,#0E0F12 85%)"></div>`;
  if (withBackdrop) html += `<div class="backdrop" style="top:${bdTop}px;--tint:${c.top};--tint-bottom:#0E0F12">${backdropScene(hue)}<div class="fadeL"></div><div class="fadeB"></div></div>
     <div class="abs" style="left:0;top:0;width:1100px;height:1080px;background:linear-gradient(90deg,${c.top}E6 0%,${c.top}99 50%,transparent 100%)"></div>`;
  return html;
}

// ---------- компоненты ----------
function poster(it, o={}){
  const w=o.w||216, h=o.h||324;
  let b='';
  if (o.watched) b += `<div class="badge b-watched">${ico('check')}</div>`;
  if (o.unw) b += `<div class="badge b-unw">${o.unw}</div>`;
  if (o.server) b += `<div class="badge b-server">На сервере</div>`;
  const pr = o.progress!=null ? `<div class="progress"><i style="width:${o.progress}%"></i></div>` : '';
  const sub = o.sub ?? (it.seasons ? seasonsWord(it.seasons) : it.y);
  return `<div class="card ${o.s||''}" style="width:${w}px"><div class="img" style="width:${w}px;height:${h}px"><div class="art">${posterArt(it,w,h,o.i||0)}${pr}</div>${b}</div>
    <div class="t">${o.title||it.t}</div><div class="st" ${o.subStyle?`style="${o.subStyle}"`:''}>${sub}</div></div>`;
}
function episode(e, o={}){
  const w=o.w||400, h=o.h||225;
  const pr = e.p!=null ? `<div class="progress"><i style="width:${e.p}%"></i></div>` : '';
  const b = e.watched ? `<div class="badge b-watched">${ico('check')}</div>` : '';
  return `<div class="card ep ${o.s||''}" style="width:${w}px"><div class="img" style="width:${w}px;height:${h}px"><div class="art">${stillArt(e.hue??165,w,h,e.i||0)}${pr}</div>${b}</div>
    <div class="t">${e.t}</div><div class="st">${e.sub}</div></div>`;
}
function castCard(c, o={}){
  return `<div class="card cast ${o.s||''}" style="width:160px;align-items:center"><div class="img" style="width:140px;height:140px"><div class="art" style="background:radial-gradient(circle at 50% 38%,${hsl(c.h,25,62)} 0 22%,transparent 23%),radial-gradient(ellipse at 50% 100%,${hsl(c.h,25,45)} 0 45%,transparent 46%),${hsl(c.h,18,24)}"></div></div>
    <div class="t" style="width:160px">${c.n}</div><div class="st" style="width:160px">${c.r}</div></div>`;
}
const btn = (txt, o={}) => `<div class="btn ${o.kind||'primary'} ${o.s||''} ${o.small?'small':''}">${o.icon?ico(o.icon):''}${txt}</div>`;
const ibtn = (icon, cap, s='') => `<div class="ib-wrap"><div class="ibtn ${s}">${ico(icon)}</div><div class="ib-cap">${s==='f'?cap:''}</div></div>`;
function ratings(r){
  const src = {imdb:['IMDb','var(--imdb)','#0E0F12'],tmdb:['TMDB','var(--tmdb)','#0E0F12'],rt:['RT','var(--rt)','#fff'],aud:['Зрители','var(--aud)','#0E0F12'],kp:['КП','#FF6600','#fff']};
  return `<div class="ratings">${Object.entries(r).map(([k,v])=>`<div class="rating"><span class="src" style="background:${src[k][1]};color:${src[k][2]}">${src[k][0]}</span>${v}</div>`).join('')}</div>`;
}
const chips = (arr, cls='genre') => `<div class="chips">${arr.map(c=>`<span class="chip ${cls}">${c}</span>`).join('')}</div>`;
const tabs = (arr, sel, f) => `<div class="tabs">${arr.map((t,i)=>`<div class="tab ${i===sel?'sel':''} ${i===f?'f':''}">${t}</div>`).join('')}</div>`;
function sidebar(cur, o={}){
  const items = [['search','Поиск'],['home','Главная'],['movie','Фильмы'],['tv','Сериалы'],['music','Музыка'],['list','Список']];
  const lower = [['gear','Настройки'],['user','Саша']];
  const it = ([i,n]) => `<div class="sb-item ${n===cur?'cur':''} ${n===o.f?'f':''}">${ico(i)}<span>${n}</span></div>`;
  return (o.expanded?'<div class="sb-scrim"></div>':'') + `<div class="sidebar ${o.expanded?'expanded':'collapsed'}">${items.map(it).join('')}<div class="sb-sep"></div>${lower.map(it).join('')}<div class="sb-spacer"></div></div>`;
}
function mrow(title, count, cards, top, o={}){
  return `<div class="mrow" style="top:${top}px;${o.left?`left:${o.left}px`:''}"><div class="mrow-h"><span class="a">${title}</span>${count!=null?`<span class="b">${count}</span>`:''}</div><div class="mrow-c" style="${o.gap?`gap:${o.gap}px;`:''}${o.pad?'margin-top:40px;':''}">${cards}</div></div>`;
}
const metaLine = arr => arr.join('<span class="dot">·</span>');

// ---------- данные экранов ----------
const darkEps1 = [
  {t:'S1 E1 · Секреты',sub:'51 мин',watched:true,i:0},
  {t:'S1 E2 · Ложь',sub:'44 мин',watched:true,i:1},
  {t:'S1 E3 · Прошлое и настоящее',sub:'осталось 35 мин',p:33,i:2},
  {t:'S1 E4 · Двойные жизни',sub:'51 мин',i:3},
  {t:'S1 E5 · Правда',sub:'45 мин',i:4},
  {t:'S1 E6 · Так сотворён мир',sub:'51 мин',i:5},
];
const continueRow = (fIdx=-1) => [
  episode({t:'S2 E5 · Дворовая война',sub:'Слово пацана · осталось 18 мин',p:70,hue:20,i:1},{s:fIdx===0?'f':''}),
  episode({t:'S1 E3 · Прошлое и настоящее',sub:'Тьма · осталось 35 мин',p:33,hue:165,i:2},{s:fIdx===1?'f':''}),
  episode({t:'Дюна: Часть вторая',sub:'осталось 1 ч 20 мин',p:52,hue:32,i:0},{s:fIdx===2?'f':''}),
  episode({t:'S3 E2 · Девять жизней',sub:'Медленные лошади · осталось 41 мин',p:12,hue:140,i:3},{s:fIdx===3?'f':''}),
  episode({t:'S1 E7 · Ночь',sub:'Эпидемия · осталось 8 мин',p:85,hue:185,i:4},{s:fIdx===4?'f':''}),
].join('');
const recentMovies = (fIdx=-1, list=['vrungel','master','cheb','oppen','dune','vyzov','kholop','t34']) =>
  list.map((k,i)=>poster(M[k],{s:i===fIdx?'f':'',i})).join('');

// ---------- экраны ----------
const SCREENS = {};

// 1. Главная
function homeHero(height, item){
  const compact = height < 500;
  return `<div class="abs" style="left:200px;top:${compact?72:110}px;width:900px">
    <div class="logo" style="font-size:${compact?88:120}px;letter-spacing:.18em">${item.logo}</div>
    <div class="body c2" style="margin-top:${compact?20:28}px">${metaLine(item.meta)}</div>
    <div style="margin-top:14px">${ratings(item.r)}</div>
    ${compact?'':`<div class="bodyL clamp3" style="margin-top:20px;max-width:860px">${item.desc}</div>`}
    ${compact?`<div class="bodyL clamp2 c2" style="margin-top:14px;max-width:860px">${item.desc}</div>`:''}
  </div>`;
}
const DARK_HERO = {logo:'ТЬМА',meta:['S1 E3 · Прошлое и настоящее','52 мин','осталось 35 мин','18+'],r:{imdb:'8.7',kp:'8.2'},
  desc:'В немецком городке Винден исчезает ребёнок. Поиски вскрывают тайны четырёх семей и петлю времени длиной в 33 года, которая связывает их прошлое, настоящее и будущее.'};
SCREENS['01-home-focus-continue'] = () => screenBg(165) + homeHero(600, DARK_HERO)
  + mrow('Продолжить просмотр', 5, continueRow(1), 600)
  + mrow('Недавно добавленные · Фильмы', 24, recentMovies(), 999)
  + sidebar('Главная');

const SLOVO_HERO = {logo:'СЛОВО ПАЦАНА',meta:['2023','1 сезон','8 эпизодов','18+','Драма, Криминал'],r:{imdb:'8.2',kp:'8.6'},
  desc:'Казань, конец 1980-х. Подросток Андрей попадает в уличную группировку и узнаёт её законы: улица даёт защиту и братство, но взамен требует всего.'};
SCREENS['01-home-focus-lower-hero-compact'] = () => screenBg(12) + homeHero(420, SLOVO_HERO)
  + mrow('Недавно добавленные · Сериалы', 12,
      [S.horses,S.slovo,S.epid,S.method,S.chern,S.trigger,S.kitchen,S.dark].map((s,i)=>poster(s,{s:i===1?'f':'',i,unw:[3,8,null,null,5,null,2,26][i]})).join(''), 420, {pad:true})
  + mrow('Русское кино', 40, recentMovies(-1,['brat','irony','moscow','stalker','solaris','ruka','leg17','up']), 918)
  + sidebar('Главная');

SCREENS['01-home-sidebar-expanded'] = () => screenBg(165) + homeHero(600, DARK_HERO)
  + mrow('Продолжить просмотр', 5, continueRow(-1), 600)
  + mrow('Недавно добавленные · Фильмы', 24, recentMovies(), 999)
  + sidebar('Главная', {expanded:true, f:'Главная'});

// 2. Библиотека
const LIB = ['brat','up','duna1','inter','irony','levi','leg17','master','moscow','incep','oppen','kholop'];
const LETTERS = '#АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'.split('');
const OFF = new Set(['Ё','Ъ','Ы','Ь','Й','Щ']);
function libHeader(title, count, sortTxt, f){
  return `<div class="abs headline" style="left:200px;top:54px;line-height:64px">${title}</div>
    <div class="abs" style="right:96px;top:54px;display:flex;gap:16px">
      ${btn(sortTxt,{kind:'secondary',icon:'sort',s:f==='sort'?'f':''})}${btn('Фильтры',{kind:'secondary',icon:'filter',s:f==='filter'?'f':''})}</div>
    <div class="abs caption c3" style="left:200px;top:118px">${count}</div>`;
}
function letters(cur, f){
  return `<div class="letters" style="left:1776px;top:206px">${LETTERS.map(l=>`<div class="letter ${OFF.has(l)?'off':''} ${l===cur&&l!==f?'cur':''} ${l===f?'f':''}">${l}</div>`).join('')}</div>`;
}
function libGrid(fIdx, top=230){
  const subs = Object.fromEntries(LIB.map(k=>[k,String(M[k].y)]));
  return `<div class="grid" style="left:200px;top:${top}px">${LIB.map((k,i)=>poster(M[k],{w:228,h:342,s:i===fIdx?'f':'',i,watched:[1,4,6].includes(i),progress:i===2?40:null,sub:subs[k]})).join('')}</div>`;
}
SCREENS['02-library-focus-poster'] = () => screenBg(220,false)
  + libHeader('Фильмы','','по названию · 175')
  + `<div class="abs" style="left:176px;top:142px">${tabs(['Библиотека','Рекомендуемое','Коллекции'],0)}</div>`
  + libGrid(3, 230) + letters('И')
  + sidebar('Фильмы');
SCREENS['02-library-focus-letters'] = () => screenBg(220,false)
  + libHeader('Фильмы','','по названию · 175')
  + `<div class="abs" style="left:176px;top:142px">${tabs(['Библиотека','Рекомендуемое','Коллекции'],0)}</div>`
  + libGrid(-1, 230) + letters('И','М')
  + sidebar('Фильмы');

// 3. Карточка фильма
const DUNE = {meta:['2024','2 ч 46 мин','12+'],genres:['Фантастика','Боевик','Драма'],dir:'Дени Вильнёв',
  r:{imdb:'8.5',tmdb:'8.1',rt:'92%',aud:'95%'},tech:['4K','HDR10','Dolby Vision','Atmos 7.1'],
  desc:'Пол Атрейдес объединяется с фрименами, чтобы отомстить заговорщикам, уничтожившим его семью. Он должен сделать выбор между любовью всей своей жизни и судьбой известной вселенной, пытаясь предотвратить ужасное будущее, которое видит только он.'};
const CAST = [{n:'Тимоти Шаламе',r:'Пол Атрейдес',h:30},{n:'Зендея',r:'Чани',h:15},{n:'Ребекка Фергюсон',r:'Джессика',h:40},{n:'Хавьер Бардем',r:'Стилгар',h:25},{n:'Остин Батлер',r:'Фейд-Раута',h:200},{n:'Флоренс Пью',r:'Ирулан',h:350},{n:'Джош Бролин',r:'Гурни Халлек',h:35},{n:'Стеллан Скарсгард',r:'Барон Харконнен',h:20},{n:'Дэйв Батиста',r:'Раббан',h:10}];
function movieHeader(top){
  return `<div class="abs" style="left:200px;top:${top}px;width:960px">
    <div class="logo" style="font-size:84px;letter-spacing:.14em">ДЮНА</div>
    <div class="title c2" style="margin-top:8px;letter-spacing:.12em;text-transform:uppercase;font-size:24px">Часть вторая</div>
    <div class="body c2" style="margin-top:20px">${metaLine(DUNE.meta)}</div>
    <div style="display:flex;gap:20px;align-items:center;margin-top:16px">${chips(DUNE.genres)}<span class="body c2">Режиссёр: <span style="color:var(--t1)">${DUNE.dir}</span></span></div>
    <div style="margin-top:20px">${ratings(DUNE.r)}</div>
    <div style="margin-top:20px">${chips(DUNE.tech,'tech')}</div>
    <div class="bodyL clamp4" style="margin-top:20px;max-width:900px">${DUNE.desc}</div>
  </div>`;
}
SCREENS['03-movie-focus-play'] = () => screenBg(32)
  + movieHeader(80)
  + `<div class="abs actions" style="left:200px;top:640px">${btn('Продолжить · осталось 1 ч 20 мин',{icon:'play',s:'f'})}${ibtn('plus','В список')}${ibtn('check','Просмотрено')}${ibtn('film','Трейлер')}${ibtn('more','Ещё')}</div>`
  + mrow('В ролях', null, CAST.map(c=>castCard(c)).join(''), 790, {gap:24});
SCREENS['03-movie-scrolled-cast-similar'] = () => screenBg(32)
  + `<div class="abs" style="left:200px;top:54px;display:flex;align-items:baseline;gap:20px"><span class="headline">Дюна: Часть вторая</span><span class="body c3">${metaLine(DUNE.meta)}</span></div>`
  + mrow('В ролях', null, CAST.map(c=>castCard(c)).join(''), 150, {gap:24})
  + mrow('Похожие', null, ['duna1','blade','arrival','inter','incep','prisoners','sicario','solaris'].map((k,i)=>poster(M[k],{s:i===1?'f':'',i})).join(''), 448, {pad:true})
  + `<div class="abs" style="left:200px;top:948px;display:flex;gap:64px">
      ${[['Студия','Legendary Pictures'],['Аудио','Русский (Dolby Atmos 7.1), Английский'],['Субтитры','Русские, Английские'],['Файл','2160p · HEVC · 58,2 ГБ']].map(([a,b])=>`<div><div class="caption c3">${a}</div><div class="body" style="margin-top:4px">${b}</div></div>`).join('')}
    </div>`;

// 4. Сериал
function showTop(tabSel, tabF){
  return `<div class="abs" style="left:200px;top:72px;width:1100px">
      <div class="logo" style="font-size:96px;letter-spacing:.24em">ТЬМА</div>
      <div class="body c2" style="margin-top:18px">${metaLine(['2017–2020','3 сезона','26 эпизодов','18+','Netflix'])}</div>
    </div>
    <div class="abs" style="left:176px;top:252px">${tabs(['Сериал','Сезон 1','Сезон 2','Сезон 3'],tabSel,tabF)}</div>`;
}
SCREENS['04-show-tab-show'] = () => screenBg(165)
  + showTop(0)
  + `<div class="abs" style="left:200px;top:336px;width:960px">
      <div style="display:flex;gap:24px;align-items:center">${chips(['Фантастика','Триллер','Драма','Детектив'])}${ratings({imdb:'8.7',kp:'8.2'})}</div>
      <div class="bodyL clamp3" style="margin-top:20px;max-width:900px">${DARK_HERO.desc}</div>
    </div>`
  + `<div class="abs actions" style="left:200px;top:530px">${btn('Продолжить S1 E3 · осталось 35 мин',{icon:'play',s:'f'})}${ibtn('plus','В список')}${ibtn('check','Просмотрено')}${ibtn('film','Трейлер')}${ibtn('more','Ещё')}</div>`
  + mrow('Сезоны', 3, [
      poster({t:'Сезон 1',h:165},{w:160,h:240,title:'10 эпизодов',sub:'',unw:8,i:0}),
      poster({t:'Сезон 2',h:150},{w:160,h:240,title:'8 эпизодов',sub:'',unw:8,i:1}),
      poster({t:'Сезон 3',h:185},{w:160,h:240,title:'8 эпизодов',sub:'',unw:8,i:2}),
    ].join(''), 648);
SCREENS['04-show-tab-season'] = () => {
  const eps = darkEps1.map((e,i)=>({...e,hue:165})).map((e,i)=>episode(e,{s:i===2?'f':''})).join('');
  return screenBg(150)
  + showTop(1)
  + `<div class="abs" style="left:200px;top:336px;width:1000px">
      <div class="headline">S1 E3 · Прошлое и настоящее</div>
      <div class="body c2" style="margin-top:12px">${metaLine(['52 мин','15 декабря 2017','просмотрено 17 из 52 мин'])}</div>
      <div style="margin-top:14px">${ratings({imdb:'8.4'})}</div>
      <div class="bodyL clamp3" style="margin-top:16px;max-width:900px">Ульрих уверен, что пропажа Микеля связана с исчезновением его брата Мадса 33 года назад. Тем временем Йонас находит в пещере странную дверь, а Шарлотта узнаёт, что смерть мальчика в лесу была не первой.</div>
    </div>`
  + mrow('Сезон 1', '10 эпизодов', eps, 676);
};

// 5. Поиск
function keyboard(fKey, lang='РУС'){
  const ru = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'.split('');
  const keys = ru.map(k=>`<div class="key ${k===fKey?'f':''}">${k}</div>`).join('')
    + `<div class="key">-</div><div class="key">${ico('mic')}</div><div class="key">0–9</div>`
    + `<div class="key w2">${ico('space')}</div><div class="key w2">${ico('back')}</div><div class="key w2" style="font-size:18px">Очистить</div>`
    + ['РУС','ENG','123'].map(l=>`<div class="key w2 lang ${l===lang?'sel':''}">${l}</div>`).join('');
  return `<div class="kb">${keys}</div>`;
}
function searchLeft(query, fKey){
  return `<div class="abs" style="left:200px;top:54px;width:444px">
    <div class="input">${ico('search')}${query?`<span>${query}</span><span class="caret"></span>`:'<span class="ph">Фильмы, сериалы, актёры</span>'}</div>
    <div style="margin-top:28px">${keyboard(fKey)}</div>
  </div>`;
}
SCREENS['05-search-empty'] = () => screenBg(220,false)
  + searchLeft('', 'А')
  + `<div class="abs" style="left:740px;top:54px;right:0">
      <div class="title">Недавние запросы</div>
      <div style="display:flex;gap:12px;margin-top:16px;flex-wrap:wrap;width:1080px">${['Тьма','Врунгель','Шаламе','Мастер и Маргарита','Чернобыль','Балабанов'].map(q=>btn(q,{kind:'secondary',small:true,icon:'history'})).join('')}</div>
    </div>`
  + mrow('Популярное на сервере', null, recentMovies(-1,['master','cheb','vrungel','dune','kholop','oppen','vyzov']), 280, {left:740})
  + mrow('Сериалы', null, [S.slovo,S.chern,S.method,S.dark,S.epid,S.trigger].map((s,i)=>poster(s,{i})).join(''), 760, {left:740})
  + sidebar('Поиск');
SCREENS['05-search-results'] = () => screenBg(220,false)
  + searchLeft('ДЮН', 'Н')
  + mrow('Фильмы', 3, [poster(M.dune,{s:'f'}),poster(M.duna1,{i:1}),poster({t:'Дюна',y:1984,h:20},{i:2})].join(''), 54, {left:740,pad:true})
  + mrow('Сериалы', 1, poster({t:'Дюна: Пророчество',seasons:1,h:40},{i:3}), 534, {left:740})
  + `<div class="mrow" style="left:1000px;top:534px"><div class="mrow-h"><span class="a">Актёры и режиссёры</span><span class="b">3</span></div>
      <div class="mrow-c">${[{n:'Дени Вильнёв',r:'Режиссёр',h:220},{n:'Тимоти Шаламе',r:'Актёр',h:30},{n:'Зендея',r:'Актриса',h:15}].map(c=>castCard(c)).join('')}</div></div>`
  + sidebar('Поиск');

// 6. Watchlist
const WL = [
  [M.dune,{server:true,sub:'2024'}],[S.horses,{sub:'4 сезона'}],[M.master,{server:true,sub:'2024'}],[{t:'Анора',y:2024,h:330},{sub:'2024'}],
  [S.slovo,{server:true,sub:'1 сезон'}],[{t:'Бруталист',y:2024,h:35},{sub:'2024'}],
  [{t:'Конклав',y:2024,h:0},{sub:'2024'}],[M.vrungel,{server:true,sub:'2025'}],[S.chern,{server:true,sub:'1 сезон'}],[{t:'Субстанция',y:2024,h:90},{sub:'2024'}],[S.detective,{sub:'4 сезона'}],[M.cheb,{server:true,sub:'2023'}],
];
SCREENS['06-watchlist'] = () => screenBg(220,false)
  + libHeader('Список','','по дате добавления · 32')
  + `<div class="abs" style="left:176px;top:142px">${tabs(['Все','Фильмы','Сериалы','Есть на сервере'],0)}</div>`
  + `<div class="grid" style="left:200px;top:230px">${WL.map(([it,o],i)=>poster(it,{...o,w:228,h:342,i,s:i===2?'f':'',sub: i===2?'<span style="color:var(--watched)">На сервере</span> · 2024':o.sub})).join('')}</div>`
  + sidebar('Список');

// 7–9. Состояния
SCREENS['07-state-loading-home'] = () => screenBg(220,false)
  + `<div class="abs" style="left:200px;top:110px">
      <div class="sk2" style="width:420px;height:96px"></div>
      <div class="sk2" style="width:520px;height:24px;margin-top:32px"></div>
      <div class="sk2" style="width:240px;height:24px;margin-top:16px"></div>
      <div class="sk2" style="width:860px;height:22px;margin-top:28px"></div>
      <div class="sk2" style="width:820px;height:22px;margin-top:12px"></div>
      <div class="sk2" style="width:600px;height:22px;margin-top:12px"></div></div>`
  + [600, 999].map((top,r)=>`<div class="mrow" style="top:${top}px"><div class="sk2" style="width:320px;height:28px;margin-top:4px"></div>
      <div class="mrow-c">${Array.from({length:r?8:5},()=>r?`<div><div class="sk" style="width:216px;height:324px"></div></div>`:`<div><div class="sk" style="width:400px;height:225px"></div><div class="sk2" style="width:300px;height:20px;margin-top:22px"></div><div class="sk2" style="width:180px;height:16px;margin-top:10px"></div></div>`).join('')}</div></div>`).join('')
  + sidebar('Главная');
SCREENS['07-state-loading-library'] = () => screenBg(220,false)
  + libHeader('Фильмы','','по названию')
  + `<div class="abs" style="left:200px;top:142px">${tabs(['Библиотека','Рекомендуемое','Коллекции'],0)}</div>`
  + `<div class="grid" style="left:200px;top:230px">${Array.from({length:12},()=>`<div><div class="sk" style="width:228px;height:342px"></div><div class="sk2" style="width:170px;height:20px;margin-top:22px"></div><div class="sk2" style="width:60px;height:16px;margin-top:10px"></div></div>`).join('')}</div>`
  + sidebar('Фильмы');
function stateBox(icon, title, text, buttons, left=200, width=1624, top=300){
  return `<div class="state-box" style="left:${left}px;width:${width}px;top:${top}px">
    <div class="state-ico">${ico(icon)}</div>
    <div class="headline" style="margin-top:32px">${title}</div>
    <div class="bodyL c2" style="margin-top:12px;max-width:820px">${text}</div>
    <div style="display:flex;gap:16px;margin-top:40px">${buttons}</div></div>`;
}
SCREENS['08-state-empty-watchlist'] = () => screenBg(220,false)
  + `<div class="abs headline" style="left:200px;top:54px;line-height:64px">Список</div>`
  + stateBox('bookmark','В списке пока пусто','Добавляйте фильмы и сериалы кнопкой «В список» на их карточке — они появятся здесь, даже если их ещё нет на сервере.',
      btn('Перейти к поиску',{icon:'search',s:'f'}), 200, 1624, 290)
  + sidebar('Список');
SCREENS['08-state-search-nothing'] = () => screenBg(220,false)
  + searchLeft('ВРНГЛ', 'Л')
  + `<div class="abs" style="left:740px;top:54px;width:1084px">
      <div class="headline">Ничего не найдено</div>
      <div class="bodyL c2" style="margin-top:12px">По запросу «врнгл» ничего нет. Проверьте написание или раскладку (РУС / ENG).</div></div>`
  + mrow('Популярное на сервере', null, recentMovies(-1,['master','cheb','vrungel','dune','kholop','oppen','vyzov']), 300, {left:740})
  + sidebar('Поиск');
SCREENS['09-state-error-server'] = () => screenBg(220,false)
  + stateBox('cloudOff','Нет связи с сервером «Домашний»','Проверьте, что сервер включён и телевизор подключён к той же сети. Последняя успешная синхронизация — сегодня в 14:32.',
      btn('Повторить',{icon:'refresh',s:'f'}) + btn('Выбрать другой сервер',{kind:'secondary',icon:'server'}), 200, 1624, 290)
  + sidebar('Главная');


// ---------- лист компонентов (высокий, не 1080) ----------
function stateRow(title, note, cells){
  return `<section style="margin-top:72px"><div class="headline">${title}</div>${note?`<div class="caption c3" style="margin-top:8px;max-width:1500px">${note}</div>`:''}
    <div style="display:flex;gap:56px;align-items:flex-end;margin-top:40px;flex-wrap:wrap">${cells.map(([l,h])=>`<div style="display:flex;flex-direction:column;gap:28px;align-items:flex-start"><div class="caption c3" style="text-transform:uppercase;letter-spacing:.08em;font-weight:700">${l}</div>${h}</div>`).join('')}</div></section>`;
}
const ST = ['Обычный','В фокусе','Нажат','Неактивен'], SC=['','f','p','d'];
const swatch = (n,h,d) => `<div style="width:180px"><div style="height:80px;border-radius:10px;background:${h};border:1px solid #ffffff1a"></div><div class="caption" style="margin-top:8px;font-weight:700">${n}</div><div class="caption c3">${h}${d?' · '+d:''}</div></div>`;
SCREENS['00-components'] = () => `<div style="padding:54px 96px 96px">
  <div class="display">PlezyTV — компоненты</div>
  <div class="bodyL c2" style="margin-top:8px;max-width:1500px">Значения из tokens.json. Фокус = белое кольцо или белая заливка + масштаб. Кнопки — скруглённые прямоугольники (12), иконочные — скруглённые квадраты (16). Тексты — пример для русской локали.</div>
  <section style="margin-top:56px"><div class="headline">Цвет</div><div style="display:flex;gap:24px;flex-wrap:wrap;margin-top:32px">
    ${swatch('bg.base','#0E0F12')}${swatch('surface.1','#1A1C21')}${swatch('surface.2','#24272D')}${swatch('surface.3','#2F333A')}${swatch('text.primary','#F2F3F5')}${swatch('text.secondary','#B4B8C0')}${swatch('text.tertiary','#7C818B')}${swatch('accent','#E5A00D')}
    ${swatch('accent.pressed','#C98A05')}${swatch('focus.ring','#FFFFFF')}${swatch('status.watched','#4CAF7A')}${swatch('status.error','#E5534B')}${swatch('rating.imdb','#F5C518')}${swatch('rating.tmdb','#01B4E4')}${swatch('rating.rtFresh','#FA320A')}${swatch('disabled.text','#5A5E66')}
  </div></section>
  <section style="margin-top:56px"><div class="headline">Типографика · Manrope</div><div style="display:grid;grid-template-columns:320px 1fr;row-gap:14px;margin-top:24px;align-items:baseline">
    ${[['display 56/64 800','display','Дюна: Часть вторая'],['headline 40/48 700','headline','Приключения капитана Врунгеля: возвращение'],['title 28/36 700','title','Продолжить просмотр'],['bodyLarge 24/34 400','bodyL','Пол Атрейдес объединяется с фрименами, чтобы отомстить заговорщикам.'],['body 22/30 500','body','S1 E3 · Прошлое и настоящее'],['label 22/28 600','label','Продолжить · осталось 35 мин'],['caption 18/24 500','caption c2','2024 · 2 ч 46 мин'],['badge 16/20 700','chip tech','4K · HDR10']].map(([a,c,t])=>`<div class="caption c3">${a}</div><div><span class="${c}">${t}</span></div>`).join('')}
  </div></section>

  ${stateRow('1. Постер 2:3 · 216×324','Фокус: картинка ×1.08 от нижнего края, кольцо 4 px с зазором 3 px, название → primary/600. Нажат: ×0.97 от фокусного. Неактивен: прозрачность 0.4. Без теней и свечения.',
    ST.map((l,i)=>[l,`<div style="padding-top:20px">${poster([M.dune,M.brat,S.dark,M.stalker][i],{s:SC[i],i})}</div>`]).concat([['Длинное название',`<div style="padding-top:20px">${poster(M.vrungel,{i:2})}</div>`]]))}
  ${stateRow('2. Кадр эпизода 16:9 · 400×225','Подпись 1: «S{n} E{m} · {название}». Подпись 2: «{длительность}» или «осталось {t}». Прогресс — полоса 6 px внутри картинки.',
    ST.map((l,i)=>[l,`<div style="padding-top:16px">${episode({...darkEps1[i+1],hue:165},{s:SC[i]})}</div>`]))}
  ${stateRow('3. Горизонтальный ряд','Заголовок title + счётчик caption. Заголовок → карточки 16, между карточками 24, между рядами 48. Сверху запас 24 px под увеличенную карточку. Ряд сам не фокусируется: его состояние — есть ли фокус внутри.',
    [['Фокус вне ряда',`<div style="position:relative;width:1700px;height:460px"><div class="mrow" style="left:0;top:20px;width:1700px;overflow:hidden">${`<div class="mrow-h"><span class="a">Недавно добавленные · Фильмы</span><span class="b">24</span></div><div class="mrow-c">${recentMovies()}</div>`}</div></div>`],
     ['Фокус внутри ряда (на 2-й карточке)',`<div style="position:relative;width:1700px;height:460px"><div class="mrow" style="left:0;top:20px;width:1700px;overflow:hidden;padding-top:0">${`<div class="mrow-h"><span class="a">Недавно добавленные · Фильмы</span><span class="b">24</span></div><div class="mrow-c" style="padding-top:28px;margin-top:0">${recentMovies(1)}</div>`}</div></div>`]])}
  ${stateRow('4a. Главная кнопка · h 64 · радиус 12','Текст обязателен: «Смотреть», «Продолжить · осталось {t}», «Продолжить S{n} E{m} · осталось {t}».',
    [['Обычный',btn('Смотреть',{icon:'play'})],['В фокусе',btn('Продолжить · осталось 35 мин',{icon:'play',s:'f'})],['Нажат',btn('Продолжить S1 E3 · осталось 35 мин',{icon:'play',s:'p'})],['Неактивен',btn('Смотреть',{icon:'play',s:'d'})]])}
  ${stateRow('4b. Вторичная кнопка','',
    [['Обычный',btn('по названию · 175',{kind:'secondary',icon:'sort'})],['В фокусе',btn('Фильтры',{kind:'secondary',icon:'filter',s:'f'})],['Нажат',btn('Трейлер',{kind:'secondary',s:'p'})],['Неактивен',btn('Версии',{kind:'secondary',s:'d'})],['Малая · h 52 (недавние запросы)',btn('Тьма',{kind:'secondary',icon:'history',small:true})]])}
  ${stateRow('4c. Иконочная кнопка · 64×64 · радиус 16','Скруглённый квадрат, не круг. Подпись под кнопкой видна только в фокусе; место под неё зарезервировано всегда.',
    [['Обычный',ibtn('plus','В список')],['В фокусе',ibtn('check','Просмотрено','f')],['Нажат',`<div class="ib-wrap"><div class="ibtn p">${ico('film')}</div><div class="ib-cap">Трейлер</div></div>`],['Неактивен',ibtn('more','Ещё','d')]])}
  ${stateRow('5. Чипы · h 36 · радиус 8','Жанр фокусируется только на карточке фильма/сериала. Тех. чипы не фокусируются.',
    ST.map((l,i)=>[l,`<span class="chip genre ${SC[i]}">${['Драма','Триллер','Фантастика','Детектив'][i]}</span>`]).concat([['Тех. чипы',chips(['4K','HDR10','Dolby Vision','Atmos 7.1','5.1'],'tech')]]))}
  ${stateRow('6. Блок оценок','Одна оценка на источник, без дублей. Порядок: IMDb, TMDB, RT, Зрители (КП — если есть). Не фокусируется: состояний фокуса нет.',
    [['Фильм',ratings({imdb:'8.5',tmdb:'8.1',rt:'92%',aud:'95%'})],['Сериал',ratings({imdb:'8.7',kp:'8.2'})],['Эпизод',ratings({imdb:'8.4'})]])}
  ${stateRow('7. Вкладки · h 52','Выбранная — primary + подчёркивание 4 px акцентом. Фокус — белая заливка. Вкладка выбирается фокусом (300 мс), без OK.',
    [['Обычный',`<div class="tabs"><div class="tab">Сезон 2</div></div>`],['Выбрана',`<div class="tabs"><div class="tab sel">Сезон 1</div></div>`],['В фокусе',`<div class="tabs"><div class="tab f">Сериал</div></div>`],['Нажат',`<div class="tabs"><div class="tab p">Сезон 3</div></div>`],['Неактивен',`<div class="tabs"><div class="tab d">Сезон 4</div></div>`]])}
  ${stateRow('8. Бейджи','Правый верхний угол, отступ 8, радиус 6. Не фокусируются. Смысл числа раскрывается подписью карточки в фокусе: «{n} непросмотренных».',
    [['Просмотрено',`<div style="padding-top:20px">${poster(M.irony,{watched:true,i:1,title:'Ирония судьбы, или С лёгким паром!'})}</div>`],['Непросмотренные',`<div style="padding-top:20px">${poster(S.dark,{unw:12,i:2})}</div>`],['… в фокусе',`<div style="padding-top:20px">${poster(S.dark,{unw:12,i:2,s:'f',sub:'12 непросмотренных',subStyle:'color:var(--accent)'})}</div>`],['Прогресс',`<div style="padding-top:20px">${poster(M.dune,{progress:52,sub:'осталось 1 ч 20 мин'})}</div>`],['На сервере',`<div style="padding-top:20px">${poster(M.master,{server:true,i:3})}</div>`]])}
  ${stateRow('9. Боковое меню · 104 / 360','Свёрнуто — только иконки на прозрачном фоне. Раскрыто — surface.1 без размытия, остальной экран затемнён плоской подложкой. Текущий раздел — полоска акцента 4×32.',
    [['Свёрнуто',`<div style="position:relative;width:136px;height:620px">${sidebar('Главная').replace('<div class="sidebar collapsed">','<div class="sidebar collapsed" style="padding-top:0">')}</div>`],
     ['Раскрыто, фокус на «Фильмы»',`<div style="position:relative;width:392px;height:620px">${sidebar('Главная',{expanded:true,f:'Фильмы'}).replace('<div class="sb-scrim"></div>','').replace('<div class="sidebar expanded">','<div class="sidebar expanded" style="padding-top:24px;border-radius:16px">')}</div>`],
     ['Пункт: обычный / текущий / фокус / нажат / неактивен',`<div style="width:328px;display:flex;flex-direction:column;gap:8px;background:var(--s1);padding:16px;border-radius:16px">
        <div class="sb-item">${ico('tv')}<span>Сериалы</span></div><div class="sb-item cur" style="margin-left:0">${ico('home')}<span>Главная</span></div><div class="sb-item f">${ico('movie')}<span>Фильмы</span></div><div class="sb-item p">${ico('list')}<span>Список</span></div><div class="sb-item d">${ico('music')}<span>Музыка</span></div></div>`]])}
  ${stateRow('10. Пункт настроек · h 88 · до 1200','Фокус: surface.3 + белая обводка 4 px, без масштаба.',
    [['',`<div style="width:1200px;display:flex;flex-direction:column;gap:8px">
      <div class="st-item">${ico('sub')}<div class="txt"><div class="a">Субтитры</div><div class="b">Обычный</div></div><div class="v">Русский</div><div class="chev">›</div></div>
      <div class="st-item f">${ico('speaker')}<div class="txt"><div class="a">Аудио</div><div class="b">В фокусе</div></div><div class="v">Оригинал</div><div class="chev">›</div></div>
      <div class="st-item p">${ico('gear')}<div class="txt"><div class="a">Качество видео</div><div class="b">Нажат</div></div><div class="v">Оригинал (4K)</div><div class="chev">›</div></div>
      <div class="st-item d">${ico('tv')}<div class="txt"><div class="a">Частота обновления</div><div class="b">Неактивен — не поддерживается устройством</div></div><div class="v">Авто</div><div class="chev">›</div></div></div>`]])}
  ${stateRow('Отступы, радиусы, анимация','',[['',`<div class="caption c2" style="font-family:Menlo,monospace;line-height:30px">space 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 | safe 96×54 | rowGap 48 · cardGap 24<br>radius card 10 · button 12 · iconButton 16 · chip 8 · badge 6 · panel 16<br>focus card ×1.08 · button ×1.05 · pressed ×0.97 · ring 4 / offset 3<br>motion focusIn 120 · focusOut 100 · press 80 · rowScroll 150 · tint 400 · debounce 300 · easeOutCubic — только scale и opacity</div>`]])}
</div>`;

// ---------- запуск ----------
function render(){
  const name = decodeURIComponent(location.hash.slice(1)) || '01-home-focus-continue';
  const el = document.getElementById('screen');
  if (!SCREENS[name]) { el.innerHTML = `<div style="padding:96px" class="title">Нет экрана «${name}». Есть: ${Object.keys(SCREENS).join(', ')}</div>`; return; }
  if (name === '00-components') { el.style.height = 'auto'; el.style.overflow = 'visible'; }
  el.innerHTML = SCREENS[name]();
  document.title = name;
  document.fonts.ready.then(()=>document.documentElement.setAttribute('data-h', el.offsetHeight));
}
window.SCREEN_NAMES = Object.keys(SCREENS);
window.addEventListener('hashchange', render);
render();
