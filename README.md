# Voice‑to‑Monday Toolkit

Hands‑free capture of Monday.com tasks from spoken commands.

---

## 1 · Requirements

* macOS (Intel **or** Apple Silicon)
* **Homebrew** (the set‑up script installs it if missing)
* Microphone (built‑in or external)
* Monday.com **API token** and default **Board ID**

---

## 2 · Install

```bash
# clone and enter the folder
$ git clone https://github.com/you/voice‑monday.git
$ cd voice‑monday

# copy env template and add your secret(s)
$ cp .env.example .env   # edit MONDAY_API_TOKEN & DEFAULT_BOARD_ID

# run the idempotent installer
$ ./setup.sh             # ✓ installs brew, ruby 3.3.4, ffmpeg, vosk…
```

Everything is downloaded into the project directory; rerunning `setup.sh` is harmless.

---

## 3 · Start the voice listener

```bash
$ ruby voice_task_server.rb
```

Leave this terminal running. Speak clearly and wait for the ⏎ prompt after each sentence.

### Supported voice patterns

| Example sentence                                                                                               | Parsed JSON stored in **queue.json**                                                                                                     |
| -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Add a task to **Pico California** workspace → **draft some document** by **June 17** (status: **In Progress**) | `{ "command":"create_task", "workspace":"pico california", "task":"draft some document", "due-date":"June 17", "status":"in progress" }` |
| Create a task to ‘Growth Team’ workspace: send beta invite emails by July 1                                    | status defaults to **todo**                                                                                                              |
| Update task 1234 in "Pico California" workspace → status Done                                                  | `{ "command":"update_task", "id":1234, "workspace":"pico california", "status":"done" }`                                                 |

*(Add more patterns in `parse_sentence` if desired.)*

---

## 4 · Review / edit

`queue.json` is a plain JSON array. Open it in your editor to tweak wording, due‑dates, etc.

---

## 5 · Send to Monday.com

```bash
$ ruby queue_processor.rb
```

Each successfully processed item disappears from the queue. Unsent items remain for the next run.

---

## 6 · How it works

1. **Speech → Text** – `ffmpeg` streams raw audio to **Vosk** for offline recognition.
2. **Parsing** – a small Ruby regex extracts workspace, task, due‑date, status (and, for updates, the ID).
3. **Queue** – tasks accumulate in `queue.json` so you can hand‑edit before they touch Monday.
4. **Upload** – GraphQL mutation to Monday.com using your API token.

---

## 7 · Customisation tips

* **Column IDs** – change them in `queue_processor.rb` (`status`, `date4`, etc.).
* **More voice commands** – extend the regex in `voice_task_server.rb`.
* **Email instead of API** – replace the GraphQL call with `Net::SMTP` to hit the board’s email‑to‑item address.

---

## 8 · Troubleshooting

* *Microphone not recognised* → replace `:0` in the `ffmpeg` command with `:1` or run `ffmpeg -f avfoundation -list_devices true -i ""` to list devices.
* *Nothing transcribed* → background noise can prevent Vosk from finalising a sentence; add a short pause.
* *API errors* → check your token scope and board ID.

---

Happy voice‑coding! 🎙️
