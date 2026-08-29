import logging
import os
import secrets
import uuid
from datetime import datetime, timezone

import psycopg
from flask import Flask, jsonify, request
from psycopg.rows import dict_row


app = Flask(__name__)
app.logger.setLevel(logging.INFO)

DATABASE_URL = os.environ["DATABASE_URL"]
CHOICES = ("rock", "paper", "scissors")


def connect():
    return psycopg.connect(DATABASE_URL, autocommit=True, row_factory=dict_row)


def calculate_result(player, computer):
    if player == computer:
        return "draw"

    wins = {
        ("rock", "scissors"),
        ("paper", "rock"),
        ("scissors", "paper"),
    }
    return "win" if (player, computer) in wins else "loss"


def public_game(row):
    created_at = row["created_at"]
    if isinstance(created_at, datetime):
        created_at = created_at.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace(
            "+00:00", "Z"
        )
    return {
        "id": str(row["id"]),
        "session_id": row["session_id"],
        "player_choice": row["player_choice"],
        "computer_choice": row["computer_choice"],
        "result": row["result"],
        "created_at": created_at,
    }


@app.get("/health")
def health():
    with connect() as connection, connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        cursor.fetchone()
    return jsonify({"status": "ok"})


@app.get("/games")
def list_games():
    with connect() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT id, session_id, player_choice, computer_choice, result, created_at
            FROM games
            ORDER BY created_at DESC
            LIMIT 5000
            """
        )
        games = [public_game(row) for row in cursor.fetchall()]
    return jsonify({"games": games})


@app.post("/games")
def create_game():
    body = request.get_json(silent=True) or {}
    session_id = body.get("sessionId")
    player_choice = body.get("playerChoice")

    if not isinstance(session_id, str) or not session_id or len(session_id) > 128:
        return jsonify({"message": "A valid sessionId is required."}), 400
    if player_choice not in CHOICES:
        return jsonify({"message": "playerChoice must be rock, paper, or scissors."}), 400

    computer_choice = secrets.choice(CHOICES)
    result = calculate_result(player_choice, computer_choice)
    game_id = uuid.uuid4()
    created_at = datetime.now(timezone.utc)
    game_key = f"{created_at.isoformat(timespec='milliseconds').replace('+00:00', 'Z')}#{game_id}"

    with connect() as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO games (
                session_id, game_key, id, player_choice, computer_choice, result, created_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, session_id, player_choice, computer_choice, result, created_at
            """,
            (
                session_id,
                game_key,
                game_id,
                player_choice,
                computer_choice,
                result,
                created_at,
            ),
        )
        game = public_game(cursor.fetchone())

    app.logger.info("game_created id=%s result=%s", game_id, result)
    return jsonify({"game": game}), 201


@app.errorhandler(Exception)
def handle_error(error):
    app.logger.exception("request_failed")
    return jsonify({"message": "Internal server error."}), 500
