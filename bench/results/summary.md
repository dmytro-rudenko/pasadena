# Pasadena vs baseline

- дата: 2026-11-22
- dataset: terminal-bench@2.0, model: anthropic/claude-opus-5-5, claude code: 2.1.330
- задачі: 10 найважчих для baseline (`bench/tasks.txt`, відібрані select-прогоном на 70 з 89 задач)
- pasadena: job `full-pasadena-d2557e26`, справжній TUI Claude Code у tmux, скриптований користувач (`bench/tui_policy.py`), 1 спроба на задачу
- baseline: job `select-baseline-f6a339ee` + `full-baseline-1301285b`, headless `claude --print`, 2–3 спроби на задачу

УВАГА: arm запущені в різних середовищах (headless проти TUI). Baseline у TUI не перезапускали за рішенням користувача: без плагіна Claude не використовує plan mode і `AskUserQuestion`, тож для нього середовища еквівалентні (TUI-smoke baseline на `build-pmars`: жодного діалогу, reward 1.0). `compare.py` таку пару навмисно не порівнює, тому звіт складено вручну з тих самих `result.json`.

## Задачі

| задача | baseline x/k | pasadena | Δ | issue |
|---|---|---|---|---|
| adaptive-rejection-sampler | 0/3 | 0/1 | = | #44 |
| caffe-cifar-10 | 0/3 | 0/1 | = | #45 |
| configure-git-webserver | 0/3 | 0/1 | = | #46 |
| dna-assembly | 2/3 | 1/1 | + | — |
| dna-insert | 1/3 | 0/1 | − | #47 |
| filter-js-from-html | 0/3 | 0/1 | = | #52 |
| make-doom-for-mips | 0/2 | 0/1 | = | #49 |
| polyglot-c-py | 0/3 | 1/1 | + | — |
| polyglot-rust-c | 0/3 | 1/1 | + | — |
| protein-assembly | 0/2 | 1/1 | + | — |

Виграші: 4, програші: 1, нічиї: 5.

## Arms

| arm | pass rate | задачі, пройдені хоч раз | вартість, $ |
|---|---|---|---|
| baseline | 3/28 (10.7%) | 2/10 (dna-assembly, dna-insert) | — |
| pasadena | 4/10 (40.0%) | 4/10 | 5.76 |

Задачі, які baseline не пройшов жодного разу за 2–3 спроби, а pasadena пройшла з першої: `polyglot-c-py`, `polyglot-rust-c`, `protein-assembly`.

На кожен провал pasadena заведено issue з розбором причини: #44, #45, #46, #47, #49, #52.

**Вердикт:** на 10 задачах, найважчих для Claude без skills, pasadena пройшла 4 (40%) з першої спроби проти 10.7% у baseline; три з чотирьох — задачі, яких baseline не пройшов жодного разу. Вибірка мала (1 спроба, 10 задач) і відібрана за провалами baseline, тож це сильний сигнал, а не статистично значуща різниця.
