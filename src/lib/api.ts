export type Choice = "rock" | "paper" | "scissors";
export type Result = "win" | "draw" | "loss";

export type Game = {
  id: string;
  session_id: string;
  player_choice: Choice;
  computer_choice: Choice;
  result: Result;
  created_at: string;
};

const apiUrl = process.env.NEXT_PUBLIC_API_URL?.replace(/\/$/, "");

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  if (!apiUrl) {
    throw new Error("NEXT_PUBLIC_API_URL is not configured.");
  }

  const response = await fetch(`${apiUrl}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...init?.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`API request failed with status ${response.status}.`);
  }

  return (await response.json()) as T;
}

export async function listGames(sessionId: string) {
  const response = await request<{ games: Game[] }>(
    `/games?sessionId=${encodeURIComponent(sessionId)}`,
  );
  return response.games;
}

export async function createGame(sessionId: string, playerChoice: Choice) {
  const response = await request<{ game: Game }>("/games", {
    method: "POST",
    body: JSON.stringify({ sessionId, playerChoice }),
  });
  return response.game;
}
