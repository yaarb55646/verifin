/// 鸣谢名单：**写死在包内**的静态数据，随版本发布。
///
/// 结构上的约定：
///
/// - 只有展示用的字段：称呼（[CreditsSupporter.name]）、可选 `handle`、可选真实头像
///   资源、可选的[头像种子][CreditsSupporter.seed]与[分组标签][CreditsSupporter.group]。
///   **没有金额、没有日期**——那些由维护者自己在仓库外记录，不从这里读、也不进备份
///   （它根本不是用户数据，而是应用内容）。
/// - 头像默认由展示名生成（见 `credits_avatar.dart`）；对方给了图片就放进
///   `assets/credits/` 并用 `avatarAsset` 指定，届时同步 pubspec 的资源声明。
/// - 加人需要发版：这是「写死在软件里」的固有代价，也是刻意的——名单不联网拉取
///   （已接受限制见 `docs/dev/known-limitations.md` L11）。
library;

/// 名单里的一个人。
class CreditsSupporter {
  const CreditsSupporter(
    this.name, {
    this.handle,
    this.avatarAsset,
    this.seed,
    this.group,
  });

  /// 展示用的称呼（昵称 / 网名 / 平台 ID）。
  final String name;

  /// 可选的附注，通常是平台账号（如 `@wh3286`），渲染在称呼下方。
  final String? handle;

  /// 真实头像资源路径；为空则按 [avatarSeed] 生成 jdenticon 头像。
  final String? avatarAsset;

  /// 头像种子；为空时取 [name]。改了展示名又想保住原头像时显式指定。
  final String? seed;

  /// 分组标签（如「特别鸣谢」）；为空表示默认组，界面不渲染组标题。
  final String? group;

  String get avatarSeed => seed ?? name;
}

/// 名单的一个分组。组由名单里 [CreditsSupporter.group] 的首次出现顺序决定，
/// 没有成员的分组不会产生——所以「特别鸣谢」当前没有内容时，界面上不会留下空标题。
class CreditsGroup {
  const CreditsGroup({required this.title, required this.members});

  /// 组标题；为空表示默认组，界面不渲染标题。
  final String? title;

  final List<CreditsSupporter> members;
}

/// 当前名单。顺序即展示顺序。
const List<CreditsSupporter> creditsSupporters = <CreditsSupporter>[
  CreditsSupporter('wh3286'),
  CreditsSupporter('RunRunxka', avatarAsset: 'assets/credits/runrunxka.jpg'),
  CreditsSupporter('Rise0223', avatarAsset: 'assets/credits/rise0223.png'),
  CreditsSupporter('懒得不想玩', avatarAsset: 'assets/credits/landebuxiangwan.jpg'),
];

/// 按分组标签首次出现的顺序分组。
List<CreditsGroup> creditsGroups({
  List<CreditsSupporter> supporters = creditsSupporters,
}) {
  final order = <String?>[];
  final buckets = <String?, List<CreditsSupporter>>{};
  for (final supporter in supporters) {
    final bucket = buckets.putIfAbsent(supporter.group, () {
      order.add(supporter.group);
      return <CreditsSupporter>[];
    });
    bucket.add(supporter);
  }
  return <CreditsGroup>[
    for (final title in order)
      CreditsGroup(
        title: title,
        members: List<CreditsSupporter>.unmodifiable(buckets[title]!),
      ),
  ];
}
