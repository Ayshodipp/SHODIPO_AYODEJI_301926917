// =============================================================================
// aggregations.js — top scorers + team win rates
// Portfolio 4, MIT 8103 Advanced Database Systems.
// Run (after seed_mongo.js):
//   mongosh kickoff_mongo aggregations.js
// =============================================================================

db = db.getSiblingDB("kickoff_mongo");
NumberLong = (n) => Long.fromNumber(Number(n));  // avoids the NumberLong(number) deprecation warning

// =========================================================================
// Aggregation 1 — Top 10 scorers across all matches.
// Pipeline:
//   $match: only completed matches with at least one scorer
//   $unwind: one doc per scorer
//   $match: drop own goals (we still report them separately if you want)
//   $group: count goals + collect minutes + last team played for
//   $sort: by goal count desc
// =========================================================================
print("====== Top 10 scorers across all matches ======");
const topScorers = db.match_reports.aggregate([
  { $match: { status: "completed", scorers: { $exists: 1, $ne: [] } } },
  { $unwind: "$scorers" },
  { $match: { "scorers.is_own_goal": { $ne: true } } },
  { $group: {
      _id: {
        player_id:   "$scorers.player_id",
        player_name: "$scorers.player_name"
      },
      goals:        { $sum: 1 },
      matches_scored_in: { $addToSet: "$match_id" },
      last_team:    { $last: "$scorers.team" },
      minutes:      { $push: "$scorers.minute" }
  }},
  { $project: {
      _id: 0,
      player_id:   "$_id.player_id",
      player_name: "$_id.player_name",
      goals:        1,
      matches_scored_in: { $size: "$matches_scored_in" },
      last_team:    1,
      first_goal_minute: { $min: "$minutes" },
      last_goal_minute:  { $max: "$minutes" }
  }},
  { $sort: { goals: -1, matches_scored_in: -1 } },
  { $limit: 10 }
]).toArray();
printjson(topScorers);

// =========================================================================
// Aggregation 2 — Team win rates (combines home + away appearances).
//   $project: emit one document per team per match, with the result.
//   $group:   per team → matches played, wins, draws, losses.
//   $addFields / $project: win_rate = wins / matches.
// =========================================================================
print("\n====== Team win rates ======");
const winRates = db.match_reports.aggregate([
  { $match: { status: "completed" } },
  // Emit two docs per match (home side and away side).
  { $facet: {
      home: [
        { $project: {
            team_id:   "$home.team_id",
            team_name: "$home.name",
            gf:         "$home.score",
            ga:         "$away.score"
        }}
      ],
      away: [
        { $project: {
            team_id:   "$away.team_id",
            team_name: "$away.name",
            gf:         "$away.score",
            ga:         "$home.score"
        }}
      ]
  }},
  { $project: { both: { $concatArrays: ["$home", "$away"] } } },
  { $unwind: "$both" },
  { $replaceRoot: { newRoot: "$both" } },
  { $group: {
      _id: { team_id: "$team_id", team_name: "$team_name" },
      matches:   { $sum: 1 },
      wins:       { $sum: { $cond: [{ $gt: ["$gf", "$ga"] }, 1, 0] } },
      draws:      { $sum: { $cond: [{ $eq: ["$gf", "$ga"] }, 1, 0] } },
      losses:     { $sum: { $cond: [{ $lt: ["$gf", "$ga"] }, 1, 0] } },
      goals_for:  { $sum: "$gf" },
      goals_against: { $sum: "$ga" }
  }},
  { $project: {
      _id: 0,
      team_id:   "$_id.team_id",
      team_name: "$_id.team_name",
      matches:   1, wins: 1, draws: 1, losses: 1,
      goals_for: 1, goals_against: 1,
      goal_difference: { $subtract: ["$goals_for", "$goals_against"] },
      win_rate: { $round: [{ $divide: ["$wins", "$matches"] }, 3] }
  }},
  { $sort: { wins: -1, goal_difference: -1 } },
  { $limit: 10 }
]).toArray();
printjson(winRates);

// =========================================================================
// Aggregation 3 — Cards by team (yellow vs red), as a sanity check.
// =========================================================================
print("\n====== Cards by team (top 10 by total cards) ======");
const cardsByTeam = db.match_reports.aggregate([
  { $match: { status: "completed", cards: { $exists: 1, $ne: [] } } },
  { $unwind: "$cards" },
  { $group: {
      _id: {
        team_id:   { $cond: [{ $eq: ["$cards.team", "home"] }, "$home.team_id", "$away.team_id"] },
        team_name: { $cond: [{ $eq: ["$cards.team", "home"] }, "$home.name",  "$away.name"] }
      },
      yellow: { $sum: { $cond: [{ $eq: ["$cards.color", "yellow"] }, 1, 0] } },
      red:    { $sum: { $cond: [{ $eq: ["$cards.color", "red"] },    1, 0] } },
      total:  { $sum: 1 }
  }},
  { $project: {
      _id: 0,
      team_id:   "$_id.team_id",
      team_name: "$_id.team_name",
      yellow: 1, red: 1, total: 1
  }},
  { $sort: { total: -1 } },
  { $limit: 10 }
]).toArray();
printjson(cardsByTeam);
