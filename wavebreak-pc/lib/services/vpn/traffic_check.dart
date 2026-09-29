/// How one through-the-tunnel probe counts toward "No traffic".
enum ProbeResult { passed, miss, notReady }

/// A probe that fails faster than this didn't wait for the network at all:
/// the engine wasn't ready (restarting after a network change, still
/// coming up). Field log: two such instant failures right after a
/// reconnect flagged a working Hysteria2 as "No traffic".
const probeFastFail = Duration(milliseconds: 1500);

/// Fast failures are retried as "not ready" at most this many times in a
/// row; after that they count as misses (a network that resets every
/// connection fails fast too).
const maxNotReadyProbes = 5;

ProbeResult classifyProbe(int? ms, Duration took, {required int notReadySoFar}) {
  if (ms != null) return ProbeResult.passed;
  if (took < probeFastFail && notReadySoFar < maxNotReadyProbes) {
    return ProbeResult.notReady;
  }
  return ProbeResult.miss;
}
