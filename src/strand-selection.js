const ROWS = 8, COLS = 6, TOTAL = 48;

const wordPool = {
  8: ["abstract","allocate","automate","backbone","callback","compiler","consumer","database","debugger","decorate",
      "dispatch","document","emulator","endpoint","evaluate","executor","explorer","failover","fastboot","firewall",
      "firmware","frontend","function","generate","graphite","hardware","hashcode","headless","hostname","instance",
      "iterator","keyboard","keystore","language","listener","manifest","metadata","microapp","monolith","mutation",
      "notebook","observer","operator","optimize","overflow","pipeline","platform","playbook","postgres","profiler",
      "protocol","provider","readonly","redirect","refactor","register","renderer","resource","response","rollback",
      "scaffold","security","selector","sequence","shutdown","simulate","snapshot","software","splitter","standard",
      "strategy","template","terminal","throttle","topology","tracking","transfer","traverse","tutorial","unittest",
      "validate","variable","viewport","watchdog","workflow",
      // general knowledge
      "absolute","accurate","achieved","acquired","activity","addition","adequate","adjacent","adjusted","admitted",
      "advanced","affected","alphabet","although","ambition","analysis","ancestor","announce","answered","apparent",
      "appetite","applause","approach","approval","argument","arranged","assembly","attached","attitude","audience",
      "balanced","becoming","behavior","birthday","boundary","breaking","breathed","building","calendar","campaign",
      "capacity","captured","carnival","category","ceremony","champion","changing","chapters","chemical","children",
      "choosing","circular","climbing","clothing","collapse","colorful","combined","complete","composed","consider",
      "constant","continue","contrast","convince","corridor","creating","creature","criminal","cultural","daughter",
      "daylight","decision","declared","defeated","delicate","delivery","describe","designed","detailed","dialogue",
      "diameter","directed","disaster","discover","distance","distinct","division","dominant","dramatic","duration",
      "educated","election","elements","elevated","emerging","emphasis","employed","enclosed","enormous","entrance",
      "equation","estimate","evidence","examined","exchange","exercise","expected","extended","external","familiar",
      "festival","finished","flexible","followed","football","forecast","formally","fraction","frequent","friendly",
      "gathered","generous","geometry","grateful","greatest","guardian","guidance","happened","heritage","highland",
      "historic","hospital","humanity","identify","imagined","improved","included","increase","indicate","industry",
      "informed","inspired","intended","interest","involved","isolated","judgment","junction","keyboard","kindness",
      "launched","learning","lifetime","likewise","listened","location","magnetic","majority","marriage","material",
      "measured","medicine","memorial","midnight","military","minister","moderate","momentum","mountain","movement",
      "multiple","national","negative","northern","observed","obtained","occasion","occupied","occurred","official",
      "opposite","ordinary","original","overcome","painting","paradise","parallel","patience","peaceful","personal",
      "physical","planning","pleasant","politics","positive","possible","powerful","practice","prepared","presence",
      "previous","princess","probable","produced","progress","promised","property","proposed","provided","question",
      "realized","received","recently","recorded","referred","regional","released","remained","remember","repeated",
      "replaced","reported","required","research","revealed","reversed","reviewed","rewarded","romantic","seasonal",
      "selected","sentence","separate","shoulder","situated","sleeping","solution","southern","speaking","specific",
      "standing","starting","strength","struggle","students","studying","subjects","suitable","supplied","survived",
      "teaching","together","tomorrow","traveled","treasure","tropical","troubled","ultimate","umbrella","universe",
      "vacation","valuable","vertical","villages","violence","visiting","volcanic","whatever","whenever","wherever",
      "wildlife","windmill","wireless","wondered","yourself"],
  7: ["ansible","backend","binding","bitwise","blocker","boolean","browser","builder","caching","cluster",
      "codegen","compile","compose","compute","console","context","control","convert","counter","cypress",
      "decoder","default","desktop","digital","discord","dynamic","elastic","encrypt","express","factory",
      "feature","flutter","gateway","generic","grafana","handler","haskell","hosting","integer","jenkins",
      "jupyter","keyword","library","logging","mapping","marshal","metrics","migrate","monitor","network",
      "package","payload","pointer","postman","process","program","project","promise","publish","reactor",
      "reducer","runtime","sandbox","scanner","scraper","service","servlet","session","setting","startup",
      "storage","swagger","testing","toolbar","trigger","upgrade","vagrant","version","webhook","webpack","wrapper",
      // general knowledge
      "ability","absence","academy","account","achieve","acquire","address","advance","against","already",
      "ancient","another","anxiety","anybody","applied","arrange","article","athlete","attempt","attract",
      "average","balance","because","believe","beneath","between","biology","brother","brought","cabinet",
      "captain","capture","careful","carried","century","certain","chapter","charity","citizen","climate",
      "collect","college","combine","comfort","command","comment","compare","compete","complex","concern",
      "conduct","confirm","connect","contain","content","contest","correct","council","country","courage",
      "covered","created","culture","current","decided","declare","defense","defined","deliver","density",
      "depends","deserve","despite","develop","devoted","diamond","discuss","disease","display","distant",
      "divided","drawing","driving","economy","edition","effects","elected","element","emotion","emperor",
      "enabled","endless","engaged","enjoyed","entered","episode","equally","escaped","evening","examine",
      "example","excited","existed","explain","explore","express","extreme","failure","falling","fashion",
      "feeling","fiction","finally","finding","fishing","fitness","flowers","focused","foreign","forever",
      "forward","freedom","further","general","genuine","getting","glacier","glowing","grammar","granted",
      "gravity","growing","habitat","harvest","healthy","hearing","helping","history","holiday","however",
      "hundred","hunting","husband","imagine","improve","include","initial","inquiry","instead","involve",
      "journey","justice","kingdom","kitchen","knowing","largely","leading","leaving","leisure","limited",
      "linking","logical","looking","machine","managed","meaning","meeting","mention","message","mineral",
      "missing","mixture","morning","musical","mystery","natural","neither","nothing","noticed","nuclear",
      "numbers","objects","obvious","offered","opinion","outside","overall","painted","parents","partial",
      "passing","pattern","payment","perhaps","picture","playing","popular","portion","poverty","present",
      "primary","private","problem","protect","provide","purpose","quality","quickly","quietly","reached",
      "reading","reality","reasons","receive","recover","reflect","regular","related","remains","removed",
      "respect","results","returns","revenue","running","science","section","serious","several","sharing",
      "shelter","showing","silence","similar","singing","sitting","society","someone","somehow","special",
      "species","stadium","staying","stories","student","subject","success","suggest","support","surface",
      "survive","teacher","telling","theater","through","tonight","tourism","towards","trading","trained",
      "trouble","turning","typical","usually","village","visible","waiting","walking","warning","weather",
      "western","whether","willing","winning","without","working","writing","younger"],
  6: ["deploy","docker","kernel","lambda","linter","logger","module","parser","plugin","portal","router",
      "schema","script","server","shader","signal","socket","source","sphinx","sprint","static","stream",
      "struct","subnet","svelte","switch","syntax","syslog","tensor","thread","toggle","tracer","tunnel",
      "update","upload","vector","widget","wizard",
      // general knowledge
      "accept","across","action","active","actual","advice","affect","afford","afraid","agency","agreed",
      "almost","always","amount","animal","answer","anyone","around","artist","aspect","attack","autumn",
      "battle","beauty","before","behind","better","beyond","border","bottle","bottom","branch","breath",
      "bridge","bright","broken","budget","burden","butter","button","camera","castle","caught","center",
      "chance","change","charge","choice","chosen","circle","cities","claims","clouds","coffee","column",
      "common","corner","cotton","couple","course","create","credit","crisis","custom","damage","danger",
      "debate","decide","deeply","degree","demand","desert","detail","differ","dinner","direct","divide",
      "dollar","double","driven","during","easily","effect","effort","either","empire","enable","energy",
      "engage","enough","entire","escape","ethnic","events","except","expect","extend","factor","failed",
      "fairly","fallen","family","famous","father","figure","finger","finish","flight","flower","follow",
      "forest","formal","former","fought","fourth","friend","frozen","future","garden","gather","global",
      "golden","ground","growth","happen","health","hearts","height","hidden","higher","highly","honest",
      "horses","hotels","houses","impact","income","indeed","inside","island","itself","joined","junior",
      "killed","launch","leader","leaves","length","lesson","letter","lights","likely","listen","little",
      "living","losing","lovely","mainly","making","manage","manner","market","master","matter","medium",
      "member","mental","method","middle","mirror","modern","moment","mother","moving","museum","myself",
      "narrow","nation","nature","nearby","nearly","needed","nights","normal","notice","object","obtain",
      "office","opened","option","orange","origin","others","output","parent","people","period","person",
      "phrase","picked","planet","player","please","plenty","pocket","police","policy","pretty","prince",
      "prison","profit","proper","proven","public","purple","pursue","raised","rather","reason","recent",
      "record","reduce","reform","region","remain","repair","repeat","report","result","return","review",
      "reward","rising","rivers","rocket","ruling","safety","sample","saving","saying","search","season",
      "second","secret","select","senior","settle","should","silver","simple","single","sister","skills",
      "slowly","smooth","social","solved","sorted","sounds","speech","spirit","spoken","spring","square",
      "stable","stated","status","steady","stolen","stones","stored","street","strong","struck","studio",
      "summer","supply","surely","system","taking","talent","target","taught","temple","tested","thanks",
      "theory","things","though","thrown","ticket","timber","timing","tissue","titles","toward","travel",
      "treaty","trying","turned","twelve","twenty","unique","united","unless","useful","valley","varied",
      "victim","vision","volume","voting","wasted","wealth","weekly","weight","widely","window","winter",
      "within","wonder","wooden","worlds","worthy","yellow"],
  5: ["stack","queue","array","cache","debug","merge","patch","clone","fetch","parse","query","route",
      "scope","shell","token","trait","build","class","const","float","index","input","model","print",
      "state","store","throw","value","watch","write","yield","async","batch","chain","chunk","codec",
      "crate","delta","embed","epoch","event","flask","frame","graph","guard","hooks","hydra","hyper",
      "infer","kafka","layer","login","macro","maven","mixin","mocha","mutex","nexus","nginx","oauth",
      "pivot","prism","proxy","rails","react","redis","regex","relay","retry","shard","slack","spawn",
      "split","squid","stash","swift","torch","trace","trunk","typed","vault","viper",
      // general knowledge
      "about","above","abuse","actor","acute","admit","adopt","adult","after","again","agent","agree",
      "ahead","alarm","album","alert","alike","alive","alley","allow","alone","along","alter","angel",
      "anger","angle","angry","ankle","annex","apart","apple","apply","arena","argue","arise","armor",
      "aroma","arose","arrow","aside","asset","atlas","avoid","award","aware","awful","basic","basis",
      "beach","began","begin","being","below","bench","bible","birth","black","blade","blame","bland",
      "blank","blast","blaze","bleed","blend","bless","blind","block","blood","bloom","blown","blues",
      "blunt","board","bonus","boost","bound","brain","brand","brave","bread","break","breed","brick",
      "bride","brief","bring","broad","broke","brook","brown","brush","buddy","buyer","cabin","candy",
      "carry","catch","cause","cease","chair","chalk","chaos","charm","chart","chase","cheap","check",
      "cheek","chess","chest","chief","child","china","choir","chord","civic","civil","claim","clash",
      "clean","clear","clerk","click","cliff","climb","clock","close","cloth","cloud","coach","coast",
      "color","comic","coral","could","count","court","cover","craft","crash","crazy","cream","creek",
      "crime","cross","crowd","crown","cruel","crush","curve","cycle","daily","dance","death","debut",
      "decay","delay","depth","dirty","disco","doubt","dough","draft","drain","drama","drawn","dream",
      "dress","drift","drink","drive","drove","drums","dryer","dying","eager","eagle","early","earth",
      "eight","elite","empty","enemy","enjoy","enter","entry","equal","error","essay","every","exact",
      "exist","extra","fable","faced","faith","false","fancy","fatal","fault","feast","fence","fever",
      "field","fifth","fifty","fight","final","first","fixed","flame","flash","fleet","flesh","floor",
      "fluid","focus","force","forge","forth","forum","found","frank","fraud","fresh","front","frost",
      "fruit","fully","funny","giant","given","glass","globe","gloom","glory","glove","going","grace",
      "grade","grain","grand","grant","grasp","grass","grave","great","green","greet","grief","grill",
      "grind","groan","gross","group","grove","grown","guest","guide","guild","guilt","guise","gusto",
      "habit","happy","harsh","heart","heavy","hence","herbs","hinge","honor","horse","hotel","house",
      "human","humor","hurry","ideal","image","imply","inner","issue","ivory","jewel","joint","joker",
      "judge","juice","juicy","jumbo","karma","kneel","knife","knock","known","label","large","laser",
      "later","laugh","learn","legal","level","light","limit","linen","liver","local","lodge","logic",
      "loose","lover","lower","lucky","lunar","magic","major","maker","manor","maple","march","match",
      "mayor","media","mercy","merit","metal","might","minor","minus","mixed","money","month","moral",
      "motor","mount","mouse","mouth","movie","music","naive","nerve","never","night","noble","noise",
      "north","noted","novel","nurse","nymph","ocean","offer","often","olive","onset","opera","order",
      "other","ought","outer","owner","oxide","ozone","paint","panel","panic","paper","party","pasta",
      "pause","peace","pearl","pedal","penny","phase","phone","photo","piano","piece","pilot","pitch",
      "pixel","pizza","place","plain","plane","plant","plate","plaza","plead","pluck","plumb","plume",
      "plunge","point","polar","poppy","posed","power","press","price","pride","prime","prior","prize",
      "probe","prone","proof","prose","proud","prove","psalm","pulse","punch","pupil","queen","quick",
      "quiet","quota","quote","radar","radio","raise","rally","ranch","range","rapid","ratio","reach",
      "ready","realm","rebel","refer","reign","relax","repay","rider","ridge","rifle","right","rigid",
      "risky","rival","river","robin","robot","rocky","roman","rough","round","royal","rugby","ruler",
      "rural","saint","salad","sauce","scale","scare","scene","scent","score","scout","seize","sense",
      "serve","seven","shade","shake","shall","shame","shape","share","shark","sharp","sheep","sheer",
      "sheet","shift","shine","shirt","shock","shoot","shore","short","shout","sight","since","sixth",
      "sixty","sized","skill","skull","slave","sleep","slice","slide","slope","small","smart","smell",
      "smile","smoke","snake","solar","solid","solve","sorry","south","space","spare","spark","speak",
      "spear","speed","spend","spice","spine","spite","spoke","spoon","sport","spray","squad","stage",
      "stain","stake","stale","stall","stamp","stand","stark","start","stays","steam","steel","steep",
      "steer","stern","stick","stiff","still","stock","stomp","stone","stood","storm","story","stove",
      "strap","straw","strip","stuck","study","stuff","style","sugar","suite","sunny","super","surge",
      "swamp","swear","sweep","sweet","swept","swift","swing","sword","table","taste","taxes","tense",
      "tenth","terms","thick","thing","think","third","thorn","those","three","tiger","tight","timer",
      "tired","title","today","topic","total","touch","tough","tower","toxic","track","trade","trail",
      "train","trait","tramp","trend","trial","tribe","trick","tried","troop","trout","truck","truly",
      "trump","trust","truth","tumor","tuner","twice","twist","ultra","under","unify","union","until",
      "upper","upset","urban","usage","usual","utter","valid","valor","valve","video","vigor","viral",
      "virus","visit","vital","vivid","vocal","voice","voter","vowel","wagon","waste","water","weary",
      "weave","wedge","weigh","weird","whale","wheat","wheel","where","which","while","white","whole",
      "whose","wider","witch","woman","women","world","worry","worse","worst","worth","would","wound",
      "wrath","wrist","wrong","yacht","young","youth","zebra","zonal"],
  4: ["bash","byte","char","code","cron","curl","dart","diff","disk","docs","dump","edit","enum","eval",
      "exec","flag","flex","flux","font","fork","func","fuse","fuzz","gist","glob","grep","guid","gzip",
      "hack","hash","helm","hook","host","html","http","icon","info","init","java","jest","json","kern",
      "keys","kube","lang","link","lint","lisp","load","lock","logs","loop","main","make","math","mesh",
      "meta","mock","node","null","opts","pack","ping","pipe","pods","poll","port","proc","prod","prop",
      "pull","push","raft","rake","repl","repo","root","rust","saas","sass","scan","seed","slug","smtp",
      "sort","spec","stub","sudo","swap","sync","tabs","task","tech","temp","test","tick","toml","tree",
      "trie","type","undo","unix","uuid","void","wasm","wiki","yaml","yarn",
      // general knowledge
      "able","acid","aged","also","area","army","atom","aunt","back","bail","bait","bake","ball","band",
      "bank","barn","base","bath","bear","beat","beef","beer","bell","belt","bend","best","bias","bike",
      "bill","bird","bite","blow","blue","boat","body","bold","bolt","bond","bone","book","boom","boot",
      "bore","born","boss","both","bowl","bulk","bull","burn","bury","busy","cafe","cage","cake","call",
      "calm","came","camp","cane","cape","card","care","cart","case","cash","cast","cave","cell","chat",
      "chin","chip","chop","cite","city","clap","clay","clip","club","clue","coal","coat","coin","cold",
      "come","cook","cool","cope","copy","cord","core","corn","cost","coup","cozy","crop","cube","cure",
      "cute","dark","data","date","dawn","days","dead","deal","dean","dear","deck","deed","deep","deer",
      "deny","desk","diet","dine","dirt","dish","dive","dock","does","done","door","dose","dove","down",
      "draw","drew","drop","drug","drum","dual","dull","dumb","dune","dusk","dust","duty","each","earn",
      "ease","east","edge","else","emit","epic","even","ever","evil","exam","face","fact","fade","fail",
      "fair","fall","fame","farm","fast","fate","fear","feel","feet","fell","felt","file","fill","film",
      "find","fine","fire","firm","fish","fist","five","flat","flew","flip","flow","foam","fold","folk",
      "fond","food","fool","foot","fore","form","fort","foul","four","free","from","fuel","full","fund",
      "fury","fuse","gain","gale","game","gang","gate","gave","gaze","gear","gene","gift","girl","give",
      "glad","glow","glue","goal","goat","goes","gold","golf","gone","good","gore","gown","grab","gray",
      "grew","grid","grim","grin","grip","grit","grow","gulf","guru","guys","hail","hair","half","hall",
      "halt","hand","hang","hard","harm","hate","have","hawk","head","heal","heap","heat","heel","held",
      "hell","helm","help","hero","hide","high","hill","hint","hire","hold","hole","holy","home","hood",
      "hope","horn","hour","huge","hull","hung","hunt","hurt","idea","idle","inch","into","iron","item",
      "jail","jazz","join","joke","jump","just","keen","keep","kick","kill","kind","king","kiss","knew",
      "know","lack","laid","lake","lamb","lamp","land","lane","last","late","lawn","lead","leaf","lean",
      "leap","left","lend","lens","less","lied","life","lift","like","lime","line","lion","list","live",
      "long","look","lore","lorn","loss","lost","loud","love","luck","lure","lush","lust","made","mail",
      "maid","male","mall","mane","many","mark","mass","mast","meal","mean","meat","meet","melt","memo",
      "mere","mesh","mild","mile","milk","mill","mind","mine","mint","miss","mist","mode","mood","moon",
      "more","most","move","much","mule","myth","nail","name","navy","near","neat","neck","need","nest",
      "news","next","nice","nine","none","noon","norm","nose","note","oath","obey","odds","once","only",
      "open","oral","oven","over","owed","owns","pace","page","paid","pain","pair","pale","palm","park",
      "part","pass","past","path","peak","peel","peer","pick","pier","pile","pine","pink","pipe","plan",
      "play","plea","plot","plow","plug","plus","poem","poet","pole","pond","pool","poor","pose","post",
      "pour","pray","prey","prop","pure","push","race","rage","rain","rank","rare","rate","read","real",
      "reap","rear","reel","rely","rent","rest","rice","rich","ride","ring","riot","rise","risk","road",
      "roam","roar","robe","role","roll","roof","room","rope","rose","ruin","rule","rush","safe","saga",
      "sail","sake","sale","salt","same","sand","sane","sang","sank","save","seal","seam","seat","seed",
      "seek","seem","seen","self","sell","send","sent","shed","ship","shoe","shop","shot","show","shut",
      "sick","side","sigh","silk","sing","sink","site","size","skin","skip","slam","slap","slim","slip",
      "slow","snap","snow","soak","soar","sock","soft","soil","sold","sole","some","song","soon","soul",
      "soup","span","spin","spit","spot","spur","star","stay","stem","step","stir","stop","stub","such",
      "suit","sung","sunk","sure","swan","swim","tail","tale","tall","tame","tape","tart","team","tear",
      "teem","tell","tend","tent","term","than","that","them","then","they","thin","this","thou","thus",
      "tide","tied","till","time","tiny","tire","toad","told","toll","tomb","tone","took","tool","torn",
      "toss","town","trap","trim","trio","trip","true","tube","tuck","tune","turn","twin","tyre","ugly",
      "upon","used","user","vain","vast","veil","vein","very","view","vile","vine","visa","wade","wage",
      "wake","walk","wall","wand","want","ward","warm","wary","wave","weak","wear","weed","week","well",
      "went","were","west","what","when","whom","wide","wife","wild","will","wind","wine","wing","wink",
      "wire","wise","wish","with","wolf","wood","wool","word","wore","work","worm","worn","wrap","wren",
      "yard","year","your","zone"]
};

function seededRng(seed) {
  let h = 0xdeadbeef ^ seed;
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h = (h ^ (h >>> 16)) >>> 0;
    return h / 4294967296;
  };
}

function hashStr(str) {
  let h = 0xdeadbeef;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 2654435761);
    h = (h << 13) | (h >>> 19);
  }
  return (h ^ (h >>> 16)) >>> 0;
}

function shuffle(arr, rng) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Word-length plans that sum exactly to 48
const PLANS = [
  // 8 words
  [8, 8, 7, 6, 5, 5, 5, 4],
  [8, 8, 7, 6, 6, 5, 4, 4],
  [8, 8, 7, 7, 5, 5, 4, 4],
  [8, 8, 7, 7, 6, 4, 4, 4],
  [8, 8, 8, 6, 5, 5, 4, 4],
  [8, 8, 8, 7, 5, 4, 4, 4],
  [8, 8, 8, 6, 6, 4, 4, 4],
  [8, 7, 7, 7, 6, 5, 4, 4],
  [8, 7, 7, 6, 6, 6, 4, 4],
  [8, 7, 7, 7, 5, 5, 5, 4],
  // 7 words
  [8, 8, 8, 6, 6, 6, 6],
  [8, 8, 8, 8, 6, 5, 5],
  [8, 8, 8, 8, 7, 5, 4],
  [8, 8, 8, 8, 6, 6, 4],
  [8, 8, 7, 7, 6, 6, 6],
  [8, 8, 7, 7, 7, 6, 5],
  [8, 8, 7, 7, 7, 7, 4],
  [8, 7, 7, 7, 7, 6, 6],
  // 6 words
  [8, 8, 8, 8, 8, 8],
];

const DIRS = [[-1,-1],[-1,0],[-1,1],[0,-1],[0,1],[1,-1],[1,0],[1,1]];

function findPath(grid, letters, idx, r, c, visited, rng) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return null;
  const key = r * COLS + c;
  if (visited & (1n << BigInt(key))) return null;
  if (grid[r][c] !== null) return null;
  if (idx === letters.length - 1) return [[r, c]];
  const newVisited = visited | (1n << BigInt(key));
  for (const [dr, dc] of shuffle([...DIRS], rng)) {
    const rest = findPath(grid, letters, idx + 1, r + dr, c + dc, newVisited, rng);
    if (rest) return [[r, c], ...rest];
  }
  return null;
}


function placeOnGrid(grid, word, path) {
  const letters = word.toUpperCase().split('');
  path.forEach(([r, c], i) => { grid[r][c] = letters[i]; });
}

function removeFromGrid(grid, path) {
  path.forEach(([r, c]) => { grid[r][c] = null; });
}

function emptyCells(grid) {
  const cells = [];
  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      if (grid[r][c] === null) cells.push([r, c]);
  return cells;
}

// Check if `word` can be spelled using only cells NOT in its own path (i.e. wrong cells)
function canSpellWithOtherCells(grid, word, ownPath) {
  const ownCells = new Set(ownPath.map(([r, c]) => `${r}:${c}`));
  const letters = word.toUpperCase().split('');

  function dfs(idx, r, c, visited) {
    if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return false;
    const key = `${r}:${c}`;
    if (ownCells.has(key)) return false; // must not use own cells
    if (visited.has(key)) return false;
    if (grid[r][c] !== letters[idx]) return false;
    if (idx === letters.length - 1) return true;
    visited.add(key);
    for (const [dr, dc] of DIRS) {
      if (dfs(idx + 1, r + dr, c + dc, visited)) { visited.delete(key); return true; }
    }
    visited.delete(key);
    return false;
  }

  for (let r = 0; r < ROWS; r++)
    for (let c = 0; c < COLS; c++)
      if (dfs(0, r, c, new Set())) return true;
  return false;
}

// Backtracking placer: places words[idx..] onto grid, must fill exactly `remaining` cells
// Tries multiple start positions per word before giving up
function backtrack(grid, words, idx, remaining, rng) {
  if (idx === words.length) return remaining === 0 ? [] : null;
  const word = words[idx];
  const letters = word.toUpperCase().split('');
  const starts = shuffle(emptyCells(grid), rng);

  for (const [sr, sc] of starts) {
    if (grid[sr][sc] !== null) continue;
    const path = findPath(grid, letters, 0, sr, sc, 0n, rng);
    if (!path) continue;
    placeOnGrid(grid, word, path);
    const rest = backtrack(grid, words, idx + 1, remaining - word.length, rng);
    if (rest !== null) return [{ word: word.toUpperCase(), path }, ...rest];
    removeFromGrid(grid, path);
  }
  return null;
}

export function generateStrandPuzzle(dateStr) {
  const rng = seededRng(hashStr('strand3:' + dateStr));

  const plan = shuffle([...PLANS[Math.floor(rng() * PLANS.length)]], rng);
  const pools = plan.map(len => shuffle([...wordPool[len]], rng));

  const indices = new Array(plan.length).fill(0);
  for (let attempt = 0; attempt < 200; attempt++) {
    if (attempt > 0) {
      let carry = true;
      for (let i = plan.length - 1; i >= 0 && carry; i--) {
        indices[i]++;
        if (indices[i] < pools[i].length) { carry = false; }
        else { indices[i] = 0; }
      }
      if (carry) break;
    }

    const words = indices.map((wi, i) => pools[i][wi]);
    if (new Set(words).size !== words.length) continue;

    const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
    const placed = backtrack(grid, words, 0, TOTAL, rng);
    // Grid is now fully filled — check no word can be spelled using other words' cells
    if (placed && placed.every(({ word, path }) => !canSpellWithOtherCells(grid, word, path))) {
      return { grid, words: placed };
    }
  }

  const grid = Array.from({ length: ROWS }, () => Array(COLS).fill(null));
  return { grid, words: [] };
}

export async function getOrCreateDailyStrand(db, dateStr) {
  const row = await db.prepare('SELECT grid, theme_words FROM strand_puzzles WHERE date = ?').bind(dateStr).first();
  if (!row) return null;
  return { grid: JSON.parse(row.grid), words: JSON.parse(row.theme_words) };
}
