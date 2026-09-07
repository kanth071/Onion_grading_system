/// URS = Unfit for Sale / below minimum quality — not obvious from the code
/// alone, so always pair it with a plain-language label wherever a grade
/// is shown to a person.
const Map<String, String> gradeLabels = {
  'Grade 1': 'Grade 1 — High Quality',
  'Grade 2': 'Grade 2 — Acceptable, Lower Quality',
  'URS': 'URS — Below Standard (Unfit for Sale)',
  'NO_DETECTION': 'No Onions Detected',
};

String gradeLabel(String grade) => gradeLabels[grade] ?? grade;

const _defectClasses = ['damaged', 'rotten', 'sprouted'];
const _defectLabels = {
  'damaged': 'Damaged',
  'rotten': 'Rotten',
  'sprouted': 'Sprouted',
};

const _allClasses = ['healthy', 'damaged', 'rotten', 'sprouted'];
const _allLabels = {
  'healthy': 'Healthy',
  'damaged': 'Damaged',
  'rotten': 'Rotten',
  'sprouted': 'Sprouted',
};

class DominantDefect {
  final String label;
  final double pct;
  DominantDefect(this.label, this.pct);
}

/// Answers "why did this batch get this grade?" instead of a bare
/// "Below Standard: X%" — picks whichever defect bucket is largest.
DominantDefect? dominantDefect(Map<String, dynamic> result) {
  final total = (result['total_onions'] as num?)?.toInt() ?? 0;
  if (total <= 0) return null;
  String? bestKey;
  int bestCount = 0;
  for (final key in _defectClasses) {
    final count = (result[key] as num?)?.toInt() ?? 0;
    if (count > bestCount) {
      bestKey = key;
      bestCount = count;
    }
  }
  if (bestKey == null) return null;
  return DominantDefect(_defectLabels[bestKey]!, (bestCount / total) * 100);
}

class MajorityClass {
  final String label;
  final double pct;
  MajorityClass(this.label, this.pct);
}

/// Answers "what's most of this batch?" - unlike dominantDefect(), healthy
/// is a candidate too, so a mostly-good batch reads "Majority: Healthy"
/// instead of being limited to defect classes.
MajorityClass? majorityClass(Map<String, dynamic> result) {
  final total = (result['total_onions'] as num?)?.toInt() ?? 0;
  if (total <= 0) return null;
  String? bestKey;
  int bestCount = -1;
  for (final key in _allClasses) {
    final count = (result[key] as num?)?.toInt() ?? 0;
    if (count > bestCount) {
      bestKey = key;
      bestCount = count;
    }
  }
  if (bestKey == null || bestCount <= 0) return null;
  return MajorityClass(_allLabels[bestKey]!, (bestCount / total) * 100);
}
