import json
import os
import secrets
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key


TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb").Table(TABLE_NAME)

CHOICES = ("rock", "paper", "scissors")


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def public_game(item):
    return {
        "id": item["id"],
        "session_id": item["session_id"],
        "player_choice": item["player_choice"],
        "computer_choice": item["computer_choice"],
        "result": item["result"],
        "created_at": item["created_at"],
    }


def calculate_result(player, computer):
    if player == computer:
        return "draw"

    wins = {
        ("rock", "scissors"),
        ("paper", "rock"),
        ("scissors", "paper"),
    }
    return "win" if (player, computer) in wins else "loss"


def list_games(session_id):
    if not session_id or len(session_id) > 128:
        return response(400, {"message": "A valid sessionId is required."})

    items = []
    query = {
        "KeyConditionExpression": Key("session_id").eq(session_id),
        "ScanIndexForward": False,
    }

    while True:
        result = table.query(**query)
        items.extend(result.get("Items", []))
        if "LastEvaluatedKey" not in result:
            break
        query["ExclusiveStartKey"] = result["LastEvaluatedKey"]

    return response(200, {"games": [public_game(item) for item in items]})


def create_game(event):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return response(400, {"message": "Request body must be valid JSON."})

    session_id = body.get("sessionId")
    player_choice = body.get("playerChoice")
    if not session_id or len(session_id) > 128:
        return response(400, {"message": "A valid sessionId is required."})
    if player_choice not in CHOICES:
        return response(400, {"message": "playerChoice must be rock, paper, or scissors."})

    computer_choice = secrets.choice(CHOICES)
    created_at = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )
    game_id = str(uuid.uuid4())
    item = {
        "session_id": session_id,
        "game_key": f"{created_at}#{game_id}",
        "id": game_id,
        "player_choice": player_choice,
        "computer_choice": computer_choice,
        "result": calculate_result(player_choice, computer_choice),
        "created_at": created_at,
    }
    table.put_item(Item=item)
    return response(201, {"game": public_game(item)})


def handler(event, _context):
    route_key = event.get("routeKey")
    if route_key == "GET /games":
        params = event.get("queryStringParameters") or {}
        return list_games(params.get("sessionId"))
    if route_key == "POST /games":
        return create_game(event)
    return response(404, {"message": "Not found."})
