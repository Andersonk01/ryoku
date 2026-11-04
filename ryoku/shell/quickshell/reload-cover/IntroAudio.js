.pragma library

// One cover draws one HackerIntro per screen, but the sound must play once.
// A .pragma library script is shared by every importer in the engine, so the
// first intro to claim it owns the speakers until it goes away.

var owner = null;

function claim(item) {
    if (owner === null)
        owner = item;
    return owner === item;
}

function release(item) {
    if (owner === item)
        owner = null;
}
