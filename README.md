# Stand Clear

Ali's NYC subway roguelike. **Play: https://buddylist.github.io/subway-roguelike/** (phone, while riding).

v2 runs on your actual ride. Pick the train you're on (it suggests lines if GPS puts you at a
station), say which way you're going, and that's it, no commute to enter.

- **At a station** the shop is open. Every station's shop comes from what that station really is
  (MTA data): transfer hubs have bigger shops, elevated stops give daylight (+1 atk), stops with an
  elevator have free restocks if it works today, the congestion zone costs more but pays more, each
  borough sells its own unit, terminals give a swipe back, and a few named stations are special
  (Bedford Av thrift, Canal St knockoffs, Times Sq chaos, Coney Island boardwalk, Yankee Stadium).
- **Between stations** your crew fights waves for as long as the ride lasts. Long tunnels mean more
  loot and more risk. Rush hour has bigger waves, late night has weird ones.
- **Where you are** comes from GPS (within ~200 m of a station on your line) and from the network
  (signal dies in the tunnel, comes back at the next stop). Manual buttons always work too, since
  GPS underground is hopeless. The fight keeps going while your phone is in your pocket and
  catches up when you look again. The run survives closing the tab.
- **Exit the system** to end a run. Results go to `?fridge=<url>` if set (see below).

## Testing without a train

Open `index.html?mock=1` (or https://buddylist.github.io/subway-roguelike/?mock=1). A panel lets
you toggle signal, put the fake GPS at any station, turn on auto-ride (20 s at a station, 45 s in
the tunnel, then the next stop) and speed it up 5x or 20x.

Locally: `python3 -m http.server` in this folder (ES modules don't load from `file://`).

## Files

- `game.js`: everything. Sections: units, stations/traits, sensors, presence (station vs riding),
  shop, fighting, fridge, mock panel, rendering.
- `stations.json`: every route's stops in order (MTA GTFS) joined with the MTA station list
  (structure, borough, elevator, transfers, congestion zone).
- `sw.js`: network-first service worker so the game reloads in a tunnel. `ping.txt` is what the
  network check fetches.

## Fridge feed

Open with `?fridge=<url>` and every finished run is POSTed there as JSON with a ready-made
`message`. Nothing listens yet: the plan is a small bridge on a `tag:pool` box with the SmartThings token.

v1 (the commute auto-battler everyone agreed was bad) is in git history at `2bca5c4`.
