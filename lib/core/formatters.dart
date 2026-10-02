String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb < 10 ? 2 : 1)} GB';
}

String formatRate(num bytesPerSecond) {
  final bits = bytesPerSecond * 8;
  if (bits < 1000) return '${bits.toStringAsFixed(0)} bps';
  if (bits < 1000000) return '${(bits / 1000).toStringAsFixed(0)} Kbps';

  final mbps = bits / 1000000;
  if (mbps < 100) return '${mbps.toStringAsFixed(1)} Mbps';
  if (mbps < 1000) return '${mbps.toStringAsFixed(0)} Mbps';

  final gbps = bits / 1000000000;
  return '${gbps.toStringAsFixed(gbps < 10 ? 2 : 1)} Gbps';
}

String formatDuration(Duration duration) {
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
