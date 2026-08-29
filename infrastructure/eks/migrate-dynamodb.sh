#!/usr/bin/env bash
set -euo pipefail

migration_region="ap-northeast-2"
migration_namespace="rps-arena"
migration_table="rps-arena-games"

{
  printf '%s\n' 'CREATE TEMP TABLE imported_games (LIKE games INCLUDING ALL);'
  printf '%s\n' '\copy imported_games (session_id, game_key, id, player_choice, computer_choice, result, created_at) FROM STDIN WITH (FORMAT csv)'
  aws dynamodb scan --region "$migration_region" --table-name "$migration_table" --output json | \
    jq -r '.Items[] | [.session_id.S, .game_key.S, .id.S, .player_choice.S, .computer_choice.S, .result.S, .created_at.S] | @csv'
  printf '%s\n' '\.'
  printf '%s\n' 'INSERT INTO games SELECT * FROM imported_games ON CONFLICT DO NOTHING;'
} | kubectl exec -i statefulset/postgres -n "$migration_namespace" -- psql -U rps -d rps -v ON_ERROR_STOP=1

kubectl exec statefulset/postgres -n "$migration_namespace" -- psql -U rps -d rps -tAc 'SELECT COUNT(*) FROM games;'
