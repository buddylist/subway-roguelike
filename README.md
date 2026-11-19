# Stand Clear

Ali's NYC subway roguelike, prototype #1. An auto-battler: pick a line and your
commute, fight whoever's on the train between stops, shop at every station.
Every station's shop has its own trait (transfer hubs have bigger shops, Bedford
Av has a free reroll, Canal St sells knockoffs, Times Sq is chaos, and so on).

## Play

It's one file with no build step. Clone the repo and open `index.html` in a browser.
On a phone, AirDrop or send yourself the file, or run `python3 -m http.server` on a
tailnet box and open `http://<box>:8000` from your phone (tailnet only).

## Rules

- 10 gold per stop, units cost 3, reroll costs 1. Buying a duplicate levels the unit up.
- Your car fights from the front (left). Units hit the enemy in front of them until one side is empty.
- Lose a fight and you lose a swipe. At 0 swipes the run is over. The last leg has a Rat King.
- Lines: L, R, G. Stations and their traits are in `LINES` at the top of the script.

## Tuning

`DIFFICULTY` sets how fast the enemies get stronger each leg. At 1.0, a bot that buys
anything it can afford wins about 60% of 9-stop commutes.

## Fridge feed

Ali wants finished runs on Tim's fridge. Open `index.html?fridge=<url>` and every
finished run is POSTed to `<url>` as JSON (with a ready-made `message` line). Nothing
listens yet: the plan is a small bridge on a `tag:pool` box that holds the SmartThings
token and pushes the message to the fridge/TV. Without `?fridge=` it just logs to the console.
