// =============================================================================
// mongo_schema.js — create kickoff_mongo.match_reports with $jsonSchema validator
// Portfolio 4, MIT 8103 Advanced Database Systems.
//
// Run:
//   mongosh kickoff_mongo mongo_schema.js
//
// MongoDB version targeted: 8.0 (installed by setup.sh).
// =============================================================================

db = db.getSiblingDB("kickoff_mongo");
NumberLong = (n) => Long.fromNumber(Number(n));  // avoids the NumberLong(number) deprecation warning

// 1) Drop and recreate the collection with a $jsonSchema validator.
db.match_reports.drop();

db.createCollection("match_reports", {
  validationLevel: "strict",
  validationAction: "error",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "KickOff Arena match report",
      required: ["match_id", "date", "pitch_id", "home", "away", "status"],
      properties: {
        _id:         {},
        match_id:    { bsonType: "long",   description: "links to SQL match_result.match_id" },
        date:        { bsonType: "date",   description: "match kick-off time (UTC)" },
        pitch_id:    { bsonType: "long",   description: "links to SQL pitch.pitch_id" },
        location_area: { bsonType: "string",
                         enum: ["Lekki","Yaba","Ikeja","Surulere"] },
        home: {
          bsonType: "object",
          required: ["team_id", "name", "score"],
          properties: {
            team_id: { bsonType: "long" },
            name:    { bsonType: "string" },
            score:   { bsonType: "int", minimum: 0, maximum: 30 }
          }
        },
        away: {
          bsonType: "object",
          required: ["team_id", "name", "score"],
          properties: {
            team_id: { bsonType: "long" },
            name:    { bsonType: "string" },
            score:   { bsonType: "int", minimum: 0, maximum: 30 }
          }
        },
        status: { enum: ["completed","abandoned","walkover"] },
        // ----- OPTIONAL arrays: vary per match (the whole point of NoSQL) -----
        scorers: {
          bsonType: "array",
          description: "Goal scorers. May be empty (0-0 draw). May include own goals.",
          items: {
            bsonType: "object",
            required: ["player_id", "minute", "team"],
            properties: {
              player_id:   { bsonType: "long" },
              player_name: { bsonType: "string" },
              minute:      { bsonType: "int", minimum: 0, maximum: 90 },
              team:         { enum: ["home","away"] },
              is_own_goal: { bsonType: "bool" },
              assist: {
                bsonType: "object",
                properties: {
                  player_id:   { bsonType: "long" },
                  player_name: { bsonType: "string" }
                }
              }
            }
          }
        },
        cards: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["player_id", "minute", "color", "team"],
            properties: {
              player_id:   { bsonType: "long" },
              player_name: { bsonType: "string" },
              minute:      { bsonType: "int", minimum: 0, maximum: 90 },
              color:       { enum: ["yellow","red"] },
              team:         { enum: ["home","away"] },
              reason:      { bsonType: "string" }
            }
          }
        },
        // Free-form notes: captain's reflections, referee report, injuries.
        notes: { bsonType: "string" },

        // Different shape per match: penalty shootout (only cup matches).
        penalty_shootout: {
          bsonType: "object",
          properties: {
            home_score: { bsonType: "int", minimum: 0, maximum: 30 },
            away_score: { bsonType: "int", minimum: 0, maximum: 30 },
            takers: {
              bsonType: "array",
              items: {
                bsonType: "object",
                required: ["player_id", "team", "scored"],
                properties: {
                  player_id:   { bsonType: "long" },
                  player_name: { bsonType: "string" },
                  team:         { enum: ["home","away"] },
                  scored:       { bsonType: "bool" }
                }
              }
            }
          }
        },
        // Different shape per match: VAR reviews (only when used).
        var_reviews: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["minute", "subject", "decision"],
            properties: {
              minute:      { bsonType: "int" },
              subject:     { bsonType: "string" },
              decision:    { enum: ["upheld","overturned","no_review"] }
            }
          }
        },
        created_at: { bsonType: "date" }
      },
      additionalProperties: false
    }
  }
});

// 2) Indexes that are part of the design (NOT the COLLSCAN→IXSCAN demo one —
//    that index is added later by collscan_ixscan.js).
db.match_reports.createIndex({ match_id: 1 }, { unique: true });
db.match_reports.createIndex({ date: 1 });
db.match_reports.createIndex({ "home.team_id": 1, date: -1 });
db.match_reports.createIndex({ "away.team_id": 1, date: -1 });
// NOTE: deliberately NO index on "scorers.player_id" — that one is created in
// collscan_ixscan.js to demonstrate the COLLSCAN → IXSCAN transition.

print("==========================================================");
print("  match_reports collection created with $jsonSchema validator.");
print("  Indexes (excluding scorers.player_id — added in collscan_ixscan.js):");
printjson(db.match_reports.getIndexes());
print("==========================================================");

// 3) Sanity test: insert one valid document, then try one invalid document.
//    The valid document has the full optional structure (scorers + cards +
//    notes + penalty_shootout + var_reviews) so we exercise every branch.
db.match_reports.insertOne({
  match_id: NumberLong(1),
  date: new Date(),
  pitch_id: NumberLong(1),
  location_area: "Lekki",
  home: { team_id: NumberLong(1), name: "Lekki Lions FC", score: 2 },
  away: { team_id: NumberLong(2), name: "Surulere Strikers", score: 2 },
  status: "completed",
  scorers: [
    { player_id: NumberLong(1), player_name: "Tunde Bello",
      minute: 12, team: "home", is_own_goal: false,
      assist: { player_id: NumberLong(2), player_name: "Ade Olawale" } },
    { player_id: NumberLong(6), player_name: "Chidi Okafor",
      minute: 33, team: "away", is_own_goal: false },
    { player_id: NumberLong(2), player_name: "Ade Olawale",
      minute: 56, team: "home", is_own_goal: false },
    { player_id: NumberLong(7), player_name: "Emeka Nwosu",
      minute: 71, team: "away", is_own_goal: false }
  ],
  cards: [
    { player_id: NumberLong(5), player_name: "Danjuma Ibrahim",
      minute: 41, color: "yellow", team: "home", reason: "late tackle" },
    { player_id: NumberLong(8), player_name: "Femi Adesanya",
      minute: 79, color: "red", team: "away", reason: "second bookable offence" }
  ],
  notes: "Cup final, decided on penalties. Pitch A in good condition.",
  penalty_shootout: {
    home_score: 4, away_score: 3,
    takers: [
      { player_id: NumberLong(1), player_name: "Tunde Bello",    team: "home", scored: true },
      { player_id: NumberLong(6), player_name: "Chidi Okafor",   team: "away", scored: true },
      { player_id: NumberLong(2), player_name: "Ade Olawale",     team: "home", scored: true },
      { player_id: NumberLong(7), player_name: "Emeka Nwosu",    team: "away", scored: false },
      { player_id: NumberLong(3), player_name: "Kunle Adeyemi",   team: "home", scored: true },
      { player_id: NumberLong(9), player_name: "Tobi Akinwale",   team: "away", scored: true },
      { player_id: NumberLong(4), player_name: "Bola Oyeleye",    team: "home", scored: true },
      { player_id: NumberLong(8), player_name: "Femi Adesanya",   team: "away", scored: false }
    ]
  },
  var_reviews: [
    { minute: 71, subject: "goal: offside check", decision: "upheld" },
    { minute: 79, subject: "second yellow → red", decision: "upheld" }
  ],
  created_at: new Date()
});

// Invalid document: missing required field "status" → validator must reject it.
try {
  db.match_reports.insertOne({
    match_id: NumberLong(2),
    date: new Date(),
    pitch_id: NumberLong(1),
    home: { team_id: NumberLong(1), name: "Lekki Lions FC", score: 0 },
    away: { team_id: NumberLong(2), name: "Surulere Strikers", score: 0 }
    // status deliberately missing
  });
  print("ERROR: invalid document was accepted — validator not enforced.");
} catch (e) {
  print("Validator rejected the invalid document as expected:");
  printjson(e.errInfo || e);
}

print("Done. Final document count:");
printjson(db.match_reports.countDocuments());
