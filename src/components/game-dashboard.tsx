"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/lib/supabase";

type Choice = "rock" | "paper" | "scissors";
type Result = "win" | "draw" | "loss";

type Game = {
  id: number;
  session_id: string;
  player_choice: Choice;
  computer_choice: Choice;
  result: Result;
  created_at: string;
};

const choices: Array<{
  value: Choice;
  label: string;
  emoji: string;
  key: string;
}> = [
  { value: "rock", label: "바위", emoji: "✊", key: "R" },
  { value: "paper", label: "보", emoji: "✋", key: "P" },
  { value: "scissors", label: "가위", emoji: "✌️", key: "S" },
];

const choiceMap = Object.fromEntries(
  choices.map((choice) => [choice.value, choice]),
) as Record<Choice, (typeof choices)[number]>;

const resultLabel: Record<Result, string> = {
  win: "승리",
  draw: "무승부",
  loss: "패배",
};

function getResult(player: Choice, computer: Choice): Result {
  if (player === computer) return "draw";

  const playerWins =
    (player === "rock" && computer === "scissors") ||
    (player === "paper" && computer === "rock") ||
    (player === "scissors" && computer === "paper");

  return playerWins ? "win" : "loss";
}

function getSessionId() {
  const storageKey = "rps-session-id";
  const existing = window.localStorage.getItem(storageKey);
  if (existing) return existing;

  const created = window.crypto.randomUUID();
  window.localStorage.setItem(storageKey, created);
  return created;
}

function formatTime(date: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(date));
}

export function GameDashboard() {
  const [games, setGames] = useState<Game[]>([]);
  const [loading, setLoading] = useState(true);
  const [playing, setPlaying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [latest, setLatest] = useState<Game | null>(null);

  useEffect(() => {
    let active = true;

    async function loadGames() {
      const { data, error: loadError } = await supabase
        .from("rps_games")
        .select("id, session_id, player_choice, computer_choice, result, created_at")
        .order("created_at", { ascending: false });

      if (!active) return;

      if (loadError) {
        setError("기록을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.");
      } else {
        setGames((data ?? []) as Game[]);
      }
      setLoading(false);
    }

    void loadGames();
    return () => {
      active = false;
    };
  }, []);

  const stats = useMemo(() => {
    const { wins, draws, losses } = games.reduce(
      (totals, game) => {
        if (game.result === "win") totals.wins += 1;
        if (game.result === "draw") totals.draws += 1;
        if (game.result === "loss") totals.losses += 1;
        return totals;
      },
      { wins: 0, draws: 0, losses: 0 },
    );
    const decided = wins + losses;
    const winRate = decided === 0 ? 0 : Math.round((wins / decided) * 100);
    return { wins, draws, losses, winRate, total: games.length };
  }, [games]);

  const play = useCallback(
    async (playerChoice: Choice) => {
      if (playing) return;

      setPlaying(true);
      setError(null);

      const computerChoice = choices[Math.floor(Math.random() * choices.length)].value;
      const result = getResult(playerChoice, computerChoice);
      const { data, error: insertError } = await supabase
        .from("rps_games")
        .insert({
          session_id: getSessionId(),
          player_choice: playerChoice,
          computer_choice: computerChoice,
          result,
        })
        .select("id, session_id, player_choice, computer_choice, result, created_at")
        .single();

      if (insertError || !data) {
        setError("경기 저장에 실패했어요. 한 번 더 선택해 주세요.");
        setPlaying(false);
        return;
      }

      const savedGame = data as Game;
      setLatest(savedGame);
      setGames((current) => [savedGame, ...current]);
      setPlaying(false);
    },
    [playing],
  );

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.repeat || playing) return;
      const selected = choices.find(
        (choice) => choice.key.toLowerCase() === event.key.toLowerCase(),
      );
      if (selected) void play(selected.value);
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [play, playing]);

  return (
    <main className="min-h-screen overflow-hidden bg-[#f4f0ff] text-[#241b35]">
      <div className="noise" aria-hidden="true" />
      <div className="mx-auto max-w-6xl px-5 py-8 sm:px-8 lg:py-12">
        <header className="mb-8 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-11 rotate-[-5deg] place-items-center rounded-2xl bg-[#5b2be0] text-xl text-white shadow-[4px_4px_0_#241b35]">
              ✌️
            </div>
            <div>
              <p className="text-xs font-black uppercase tracking-[0.24em] text-[#744bea]">
                One more round
              </p>
              <h1 className="text-xl font-black tracking-tight sm:text-2xl">
                가위바위보 아레나
              </h1>
            </div>
          </div>
          <div className="rounded-full border-2 border-[#241b35] bg-white px-4 py-2 text-xs font-black shadow-[3px_3px_0_#241b35] sm:text-sm">
            총 {stats.total}판
          </div>
        </header>

        <section className="grid gap-6 lg:grid-cols-[1.35fr_0.65fr]">
          <div className="game-panel relative rounded-[2rem] border-2 border-[#241b35] bg-[#5b2be0] p-5 shadow-[8px_8px_0_#241b35] sm:p-8">
            <div className="absolute right-5 top-5 rounded-full border-2 border-white/60 px-3 py-1 text-[10px] font-black uppercase tracking-[0.2em] text-white/80">
              Best of forever
            </div>
            <div className="max-w-lg pt-12 sm:pt-5">
              <p className="mb-2 text-sm font-bold text-[#d9ff72]">준비됐나요?</p>
              <h2 className="text-4xl font-black leading-[0.98] tracking-[-0.055em] text-white sm:text-6xl">
                하나를 골라
                <br />승부를 내세요.
              </h2>
              <p className="mt-4 max-w-md text-sm font-medium leading-6 text-white/70 sm:text-base">
                선택하는 즉시 컴퓨터와 대결하고, 모든 결과는 자동으로 저장돼요.
              </p>
            </div>

            <div className="mt-8 grid grid-cols-3 gap-3 sm:mt-12 sm:gap-4">
              {choices.map((choice) => (
                <button
                  key={choice.value}
                  type="button"
                  disabled={playing}
                  onClick={() => void play(choice.value)}
                  className="choice-button group relative min-h-36 rounded-[1.5rem] border-2 border-[#241b35] bg-white px-2 py-5 text-center shadow-[5px_5px_0_#241b35] transition disabled:cursor-wait disabled:opacity-60 sm:min-h-44"
                  aria-label={`${choice.label} 선택`}
                >
                  <span className="block text-5xl transition-transform group-hover:scale-110 sm:text-7xl" aria-hidden="true">
                    {choice.emoji}
                  </span>
                  <span className="mt-3 block text-lg font-black sm:text-xl">
                    {choice.label}
                  </span>
                  <span className="mt-1 inline-flex rounded-md bg-[#eee8ff] px-2 py-0.5 text-[10px] font-black text-[#744bea]">
                    KEY {choice.key}
                  </span>
                </button>
              ))}
            </div>

            {latest && (
              <div
                className={`result-card mt-6 flex flex-col items-center justify-between gap-4 rounded-[1.5rem] border-2 border-[#241b35] p-4 sm:flex-row sm:p-5 result-${latest.result}`}
                aria-live="polite"
              >
                <div className="flex items-center gap-4">
                  <div className="text-4xl" aria-hidden="true">
                    {choiceMap[latest.player_choice].emoji}
                  </div>
                  <div>
                    <p className="text-xs font-black uppercase tracking-[0.18em] opacity-60">
                      방금 결과
                    </p>
                    <p className="text-2xl font-black">
                      {resultLabel[latest.result]}!
                    </p>
                  </div>
                </div>
                <p className="rounded-full border-2 border-current px-4 py-2 text-sm font-black">
                  나 {choiceMap[latest.player_choice].label} · 컴퓨터 {choiceMap[latest.computer_choice].label}
                </p>
              </div>
            )}

            {error && (
              <p className="mt-5 rounded-xl border-2 border-[#241b35] bg-[#ff9eaa] px-4 py-3 text-sm font-black" role="alert">
                {error}
              </p>
            )}
          </div>

          <aside className="flex flex-col gap-6">
            <section className="rounded-[2rem] border-2 border-[#241b35] bg-[#d9ff72] p-6 shadow-[7px_7px_0_#241b35]">
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-xs font-black uppercase tracking-[0.2em] opacity-55">누적 승률</p>
                  <p className="mt-1 text-6xl font-black tracking-[-0.07em]">
                    {loading ? "--" : stats.winRate}
                    <span className="text-2xl">%</span>
                  </p>
                </div>
                <div className="grid size-12 place-items-center rounded-full border-2 border-[#241b35] bg-white text-2xl shadow-[3px_3px_0_#241b35]" aria-hidden="true">
                  ↗
                </div>
              </div>
              <div className="mt-6 h-3 overflow-hidden rounded-full border-2 border-[#241b35] bg-white">
                <div className="h-full bg-[#5b2be0] transition-all duration-500" style={{ width: `${stats.winRate}%` }} />
              </div>
              <p className="mt-3 text-xs font-bold opacity-60">무승부를 제외한 경기 기준</p>
            </section>

            <section className="grid grid-cols-3 gap-3">
              {([
                ["승", stats.wins, "bg-[#c7b6ff]"],
                ["무", stats.draws, "bg-white"],
                ["패", stats.losses, "bg-[#ff9eaa]"],
              ] as const).map(([label, value, color]) => (
                <div key={label} className={`rounded-2xl border-2 border-[#241b35] p-4 text-center shadow-[4px_4px_0_#241b35] ${color}`}>
                  <p className="text-[10px] font-black uppercase tracking-[0.18em] opacity-50">{label}</p>
                  <p className="mt-1 text-3xl font-black">{loading ? "-" : value}</p>
                </div>
              ))}
            </section>

            <section className="min-h-72 flex-1 rounded-[2rem] border-2 border-[#241b35] bg-white p-5 shadow-[7px_7px_0_#241b35]">
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-lg font-black">최근 경기</h2>
                <span className="rounded-full bg-[#eee8ff] px-3 py-1 text-[10px] font-black text-[#744bea]">LIVE RECORD</span>
              </div>

              {loading ? (
                <div className="grid min-h-48 place-items-center text-sm font-bold text-[#766f80]">기록 불러오는 중…</div>
              ) : games.length === 0 ? (
                <div className="grid min-h-48 place-items-center text-center text-sm font-bold text-[#766f80]">첫 승부를 시작해 보세요.</div>
              ) : (
                <ol className="space-y-2">
                  {games.slice(0, 6).map((game) => (
                    <li key={game.id} className="flex items-center gap-3 rounded-xl border border-[#ddd6e8] bg-[#faf8ff] p-3">
                      <span className="text-2xl" aria-hidden="true">{choiceMap[game.player_choice].emoji}</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-black">
                          {choiceMap[game.player_choice].label} vs {choiceMap[game.computer_choice].label}
                        </p>
                        <p className="text-[10px] font-bold text-[#8a8294]">{formatTime(game.created_at)}</p>
                      </div>
                      <span className={`result-badge badge-${game.result}`}>{resultLabel[game.result]}</span>
                    </li>
                  ))}
                </ol>
              )}
            </section>
          </aside>
        </section>

        <footer className="mt-8 flex flex-col justify-between gap-2 text-xs font-bold text-[#756d80] sm:flex-row">
          <p>모든 경기 기록은 Supabase에 안전하게 저장됩니다.</p>
          <p>가위는 보를 이기고 · 보는 바위를 이기고 · 바위는 가위를 이겨요</p>
        </footer>
      </div>
    </main>
  );
}
