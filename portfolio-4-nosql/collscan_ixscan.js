// =============================================================================
// collscan_ixscan.js — COLLSCAN → IXSCAN demonstration.
// Portfolio 4, MIT 8103 Advanced Database Systems.
// Run (after seed_mongo.js):
//   mongosh kickoff_mongo collscan_ixscan.js
//
// The same find() query is run twice with explain("executionStats"):
//   1) BEFORE createIndex on scorers.player_id   → COLLSCAN
//   2) AFTER  createIndex on scorers.player_id   → IXSCAN
// Capture both explain outputs as evidence for the LMS submission.
// =============================================================================

db = db.getSiblingDB("kickoff_mongo");
NumberLong = (n) => Long.fromNumber(Number(n));  // avoids the NumberLong(number) deprecation warning

// Pick a player_id that exists in the seed data (players per team are 1..6000).
const PLAYER_ID = NumberLong(7 * 10 + 0);   // first player of team 7

print(`Target player_id = ${PLAYER_ID}`);
print(`Count of matches in which this player scored (sanity): ${db.match_reports.countDocuments({ "scorers.player_id": PLAYER_ID })}`);

// ---------------------------------------------------------------------------
// 1) BEFORE the index — COLLSCAN.
//    Drop the index in case it already exists (re-runnable).
// ---------------------------------------------------------------------------
try { db.match_reports.dropIndex("scorers.player_id_1"); } catch (e) { print("(index not present yet - fine)"); }
print("\n====== BEFORE — explain('executionStats') ======");
const beforeExplain = db.match_reports
  .find({ "scorers.player_id": PLAYER_ID })
  .explain("executionStats");

// Print only the bits that matter for the screenshot.
print("queryPlanner.winningPlan.stage = " + beforeExplain.queryPlanner.winningPlan.stage);
// For a multi-key index the stage is "COLLSCAN" before the index is added.
print("executionStats.totalDocsExamined = " + beforeExplain.executionStats.totalDocsExamined);
print("executionStats.totalKeysExamined = " + beforeExplain.executionStats.totalKeysExamined);
print("executionStats.executionTimeMillis = " + beforeExplain.executionStats.executionTimeMillis);
print("executionStats.nReturned = " + beforeExplain.executionStats.nReturned);
print("--- full plan ---");
printjson(beforeExplain.queryPlanner);
printjson(beforeExplain.executionStats);

// ---------------------------------------------------------------------------
// 2) Create the index — multi-key index on the array element.
// ---------------------------------------------------------------------------
print("\n====== Creating multi-key index on scorers.player_id ======");
db.match_reports.createIndex({ "scorers.player_id": 1 });
printjson(db.match_reports.getIndexes());

// ---------------------------------------------------------------------------
// 3) AFTER the index — IXSCAN.
// ---------------------------------------------------------------------------
print("\n====== AFTER — explain('executionStats') ======");
const afterExplain = db.match_reports
  .find({ "scorers.player_id": PLAYER_ID })
  .explain("executionStats");

print("queryPlanner.winningPlan.stage = " + afterExplain.queryPlanner.winningPlan.stage);
// For a multi-key index the stage is now "IXSCAN" followed by "FETCH".
print("executionStats.totalDocsExamined = " + afterExplain.executionStats.totalDocsExamined);
print("executionStats.totalKeysExamined = " + afterExplain.executionStats.totalKeysExamined);
print("executionStats.executionTimeMillis = " + afterExplain.executionStats.executionTimeMillis);
print("executionStats.nReturned = " + afterExplain.executionStats.nReturned);
print("--- full plan ---");
printjson(afterExplain.queryPlanner);
printjson(afterExplain.executionStats);

// ---------------------------------------------------------------------------
// 4) Before/after summary table — print it for the screenshot.
// ---------------------------------------------------------------------------
print("\n====== BEFORE vs AFTER summary ======");
print("Stage before: " + beforeExplain.queryPlanner.winningPlan.stage + "   Stage after: " + afterExplain.queryPlanner.winningPlan.stage + " -> " + (afterExplain.queryPlanner.winningPlan.inputStage||{}).stage);
print(`COLLSCAN totalDocsExamined = ${beforeExplain.executionStats.totalDocsExamined}`);
print(`COLLSCAN executionTimeMillis = ${beforeExplain.executionStats.executionTimeMillis}`);
print(`IXSCAN  totalKeysExamined  = ${afterExplain.executionStats.totalKeysExamined}`);
print(`IXSCAN  totalDocsExamined   = ${afterExplain.executionStats.totalDocsExamined}`);
print(`IXSCAN  executionTimeMillis = ${afterExplain.executionStats.executionTimeMillis}`);

// Leave the index in place so subsequent runs in P5 / final documentation
// can also use it.
