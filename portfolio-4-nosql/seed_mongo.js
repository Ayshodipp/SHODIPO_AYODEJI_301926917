// =============================================================================
// seed_mongo.js — generate 40 000+ match-report documents (variable shape)
// Portfolio 4, MIT 8103 Advanced Database Systems.
// Run:
//   mongosh kickoff_mongo seed_mongo.js
// =============================================================================

db = db.getSiblingDB("kickoff_mongo");
NumberLong = (n) => Long.fromNumber(Number(n));  // avoids the NumberLong(number) deprecation warning

// Seedable PRNG so re-runs are deterministic.
function mulberry32(a) {
  return function() {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rng = mulberry32(20261107);
const rand   = n => Math.floor(rng() * n);
const pick   = arr => arr[rand(arr.length)];
const chance = p => rng() < p;

// Names reused from bulk_seed.py for consistency.
const NG_FIRST = ["Tunde","Ade","Kunle","Bola","Danjuma","Chidi","Emeka","Femi",
                  "Tobi","Seyi","Bayo","Tope","Yemi","Gbenga","Nnamdi","Uche",
                  "Yakubu","Ifeanyi","Saheed","Kemi","Nike","Folake","Adaeze",
                  "Chioma","Zainab","Aisha","Fatima","Joy","Grace","Maryam"];
const NG_LAST  = ["Bello","Olawale","Adeyemi","Oyeleye","Ibrahim","Okafor","Nwosu",
                  "Adesanya","Akinwale","Olawepo","Adebayo","Ojo","Oyetola","Sanusi",
                  "Bashir","Okoro","Eze","Mohammed","Idris","Ezekwesili","Abubakar",
                  "Okonkwo","Ogunleye","Adewale","Ehigiator"];
const AREAS = ["Lekki","Yaba","Ikeja","Surulere"];
const PITCHES = [
  { pitch_id: 1,  area: "Lekki"     },
  { pitch_id: 2,  area: "Lekki"     },
  { pitch_id: 3,  area: "Lekki"     },
  { pitch_id: 4,  area: "Yaba"      },
  { pitch_id: 5,  area: "Yaba"      },
  { pitch_id: 6,  area: "Yaba"      },
  { pitch_id: 7,  area: "Ikeja"     },
  { pitch_id: 8,  area: "Ikeja"     },
  { pitch_id: 9,  area: "Ikeja"     },
  { pitch_id: 10, area: "Surulere"  },
  { pitch_id: 11, area: "Surulere"  },
  { pitch_id: 12, area: "Surulere"  }
];
const TEAM_PREFIXES = ["Lekki","Yaba","Ikeja","Surulere","Mainland","Island",
                       "Victoria","Festac","Apapa","Agege"];
const TEAM_SUFFIXES = ["Lions FC","Strikers","United","Rovers","Athletic","FC",
                       "City","Warriors","Eagles","Galaxy"];

const TARGET_DOCS = 40_000;

// Wipe and start from the single sanity document inserted by mongo_schema.js.
db.match_reports.deleteMany({});

// Pre-build a roster of teams (ids 1..600) and a small player pool per team.
const teams = [];
for (let i = 1; i <= 600; i++) {
  teams.push({
    team_id: NumberLong(i),
    name: `${pick(TEAM_PREFIXES)} ${pick(TEAM_SUFFIXES)} ${i}`,
    players: Array.from({length: 8}, (_, k) => ({
      player_id: NumberLong(i * 10 + k),
      player_name: `${pick(NG_FIRST)} ${pick(NG_LAST)}`
    }))
  });
}

// Insert in batches of 1 000 — much faster than one-at-a-time.
const BATCH = 1000;
const totalBatches = Math.ceil(TARGET_DOCS / BATCH);

// Anchor on today, ±1 year window (rolling, never expires).
const today = new Date();
const windowMs = 365 * 24 * 3600 * 1000;

function randomDate() {
  return new Date(today.getTime() - windowMs + Math.floor(rng() * 2 * windowMs));
}

function makeDocument(matchId) {
  const pitch = pick(PITCHES);
  const home = pick(teams);
  let away = pick(teams);
  while (away.team_id === home.team_id) away = pick(teams);

  const homeScore = rand(8);
  const awayScore = rand(8);
  const status = chance(0.97) ? "completed"
                : chance(0.5) ? "abandoned"
                : "walkover";

  const doc = {
    match_id: NumberLong(matchId),
    date: randomDate(),
    pitch_id: NumberLong(pitch.pitch_id),
    location_area: pitch.area,
    home: { team_id: home.team_id, name: home.name, score: homeScore },
    away: { team_id: away.team_id, name: away.name, score: awayScore },
    status,
    created_at: new Date()
  };

  // Scorers — only when status is completed and the score > 0.
  if (status === "completed" && (homeScore + awayScore) > 0) {
    doc.scorers = [];
    for (let s = 0; s < homeScore; s++) {
      const p = pick(home.players);
      doc.scorers.push({
        player_id:   p.player_id,
        player_name: p.player_name,
        minute:      1 + rand(89),
        team:        "home",
        is_own_goal: chance(0.05),
        assist: chance(0.6) ? {
          player_id:   pick(home.players).player_id,
          player_name: pick(home.players).player_name
        } : undefined
      });
    }
    for (let s = 0; s < awayScore; s++) {
      const p = pick(away.players);
      doc.scorers.push({
        player_id:   p.player_id,
        player_name: p.player_name,
        minute:      1 + rand(89),
        team:        "away",
        is_own_goal: chance(0.05),
        assist: chance(0.6) ? {
          player_id:   pick(away.players).player_id,
          player_name: pick(away.players).player_name
        } : undefined
      });
    }
  }

  // Cards — about half of completed matches have at least one card.
  if (status === "completed" && chance(0.55)) {
    doc.cards = [];
    const nCards = 1 + rand(4);
    for (let c = 0; c < nCards; c++) {
      const isHome = chance(0.5);
      const sideTeam = isHome ? home : away;
      const p = pick(sideTeam.players);
      doc.cards.push({
        player_id:   p.player_id,
        player_name: p.player_name,
        minute:      1 + rand(89),
        color:       chance(0.85) ? "yellow" : "red",
        team:         isHome ? "home" : "away",
        reason:      pick(["late tackle","dissent","handball",
                           "simulation","second bookable offence","serious foul play"])
      });
    }
  }

  // Notes — about 30% of matches.
  if (chance(0.3)) {
    doc.notes = pick([
      "Pitch was waterlogged in patches but playable.",
      "Late kick-off due to referee delay.",
      "Captain's report: well-officiated.",
      "Top-of-the-table clash, large crowd.",
      "Rescheduled from earlier in the week due to rain.",
      "End-to-end affair, both keepers in top form.",
      "Walkover after away team failed to field minimum 5 players."
    ]);
  }

  // Penalty shootout — only on a draw AND only ~2% of matches (cup finals etc).
  if (status === "completed" && homeScore === awayScore && chance(0.02)) {
    const homePS = 3 + rand(3);
    const awayPS = homeScore === awayScore ? (chance(0.5) ? homePS - 1 : homePS) : homePS;
    doc.penalty_shootout = { home_score: homePS, away_score: Math.max(awayPS, 0), takers: [] };
    for (let k = 0; k < 5; k++) {
      doc.penalty_shootout.takers.push({
        player_id:   pick(home.players).player_id,
        player_name: pick(home.players).player_name,
        team:         "home",
        scored:       chance(0.75)
      });
      doc.penalty_shootout.takers.push({
        player_id:   pick(away.players).player_id,
        player_name: pick(away.players).player_name,
        team:         "away",
        scored:       chance(0.75)
      });
    }
  }

  // VAR reviews — ~10% of completed matches.
  if (status === "completed" && chance(0.1)) {
    doc.var_reviews = [{
      minute: 1 + rand(89),
      subject: "goal: offside check",
      decision: pick(["upheld","overturned","no_review"])
    }];
  }

  // undefined would be stored as null and fail the validator: drop missing assists.
  (doc.scorers || []).forEach(x => { if (x.assist === undefined) delete x.assist; });
  return doc;
}

print(`Generating ${TARGET_DOCS} match-report documents in ${totalBatches} batches…`);
let inserted = 0;
for (let b = 0; b < totalBatches; b++) {
  const batch = [];
  for (let i = 0; i < BATCH && inserted < TARGET_DOCS; i++, inserted++) {
    batch.push(makeDocument(inserted + 1));
  }
  db.match_reports.insertMany(batch, { ordered: false });
  if (b % 5 === 0) {
    print(`  … batch ${b + 1}/${totalBatches} — total inserted = ${inserted}`);
  }
}

print("==========================================================");
print(`Done. match_reports.countDocuments() = ${db.match_reports.countDocuments()}`);
print("Three sample documents (to show the variable shape):");
printjson(db.match_reports.findOne({}, { _id: 0 }));
printjson(db.match_reports.findOne({ penalty_shootout: { $exists: 1 } }, { _id: 0 }));
printjson(db.match_reports.findOne({ var_reviews: { $exists: 1 } }, { _id: 0 }));
print("==========================================================");
