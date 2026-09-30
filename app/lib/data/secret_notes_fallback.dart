import '../models/secret_note.dart';

/// 星语离线兜底：未联网或后端未配置时展示，与后端默认值保持一致。
/// 正式内容以「APP配置」里的 secret_notes 为准，改后台 APP 联网即同步。
const List<SecretNote> kSecretNotesFallback = [
  SecretNote(
    id: 'seed-1',
    text: '被你找到啦。这里是只属于我们的一片小星空——以后想对你说的话，我都会藏在这儿的星星里。',
    date: '2026-09-16',
  ),
  SecretNote(
    id: 'seed-2',
    text: '以后不用等天晴了，这里的星星，每天都会为你亮着。',
    date: '2026-09-16',
  ),
  SecretNote(
    id: 'seed-3',
    text: '今天路过一家小店，橱窗里的小东西特别像你。下次带你去看，好不好？',
    date: '2026-09-16',
  ),
];
