import test from "node:test";
import assert from "node:assert/strict";
import { createMusicQueue } from "../js/music/player/model/queue.mjs";

test("an album queue navigates in order and stops at its boundaries", () => {
  const queue = createMusicQueue();
  queue.replace([{ id: 1 }, { id: 2 }]);
  assert.equal(queue.previousIndex(), null);
  assert.equal(queue.nextIndex(), 0);
  queue.select(0);
  assert.equal(queue.current().id, 1);
  assert.equal(queue.nextIndex(), 1);
  queue.select(1);
  assert.equal(queue.previousIndex(), 0);
  assert.equal(queue.nextIndex(), null);
  queue.clear();
  assert.deepEqual(queue.snapshot(), { tracks: [], index: -1 });
});

test("queue snapshots do not expose mutable track data", () => {
  const tracks = [{ id: 1 }];
  const queue = createMusicQueue();
  queue.replace(tracks);
  tracks[0].id = 2;
  const snapshot = queue.snapshot();
  snapshot.tracks[0].id = 3;
  assert.equal(queue.snapshot().tracks[0].id, 1);
});
