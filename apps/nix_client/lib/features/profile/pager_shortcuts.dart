import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/nix_state.dart';
import '../design/nix_bilingual_label.dart';
import '../dialogs/nix_symbol_picker.dart';
import '../navigation/workspace_image.dart';
import 'pager_housing.dart';

class PagerShortcuts extends StatefulWidget {
  const PagerShortcuts({super.key});

  @override
  State<PagerShortcuts> createState() => _PagerShortcutsState();
}

class _PagerShortcutsState extends State<PagerShortcuts> {
  final _scroll = ScrollController();
  bool _before = false;
  bool _after = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateArrows);
  }

  void _updateArrows() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    final before = position.extentBefore > 1;
    final after = position.extentAfter > 1;
    if (before != _before || after != _after) {
      setState(() {
        _before = before;
        _after = after;
      });
    }
  }

  void _move(int direction, bool reducedMotion) {
    final position = _scroll.position;
    final target =
        (position.pixels + position.viewportDimension * .8 * direction)
            .clamp(0.0, position.maxScrollExtent);
    if (reducedMotion || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NixState>();
    final groups =
        state.spaces.where((space) => !space.isDirectMessages).toList();
    final channels = groups.expand((space) => space.channels).toList();
    final friends =
        state.directMessages.where((dm) => !dm.isSavedMessages).toList();
    final longest =
        math.max(groups.length, math.max(channels.length, friends.length));
    if (longest == 0) return const SizedBox.shrink();

    final themeScope = PagerThemeScope.of(context);
    final ink = themeScope?.ink ?? state.settings.pagerLcdColor.inkColor;
    final rule = themeScope?.rule ?? state.settings.pagerLcdColor.ruleColor;

    void open(VoidCallback select) {
      state.closeProfileOverlay();
      select();
    }

    final shortcuts = [
      for (var i = 0; i < longest; i++) ...[
        if (i < groups.length)
          _Shortcut(
            groups[i].name,
            'Grupo',
            WorkspaceImage(path: groups[i].customImagePath, size: 30, fallback: NixSymbol(groups[i].iconEmoji ?? groups[i].initials, size: 15, color: ink)),
            () => open(() => state.selectSpace(groups[i])),
            ink,
          ),
        if (i < channels.length)
          _Shortcut(
            channels[i].name,
            'Canal',
            WorkspaceImage(path: channels[i].customImagePath, size: 30, fallback: Icon(channels[i].icon, size: 18, color: ink)),
            () => open(() => state.selectChannel(channels[i])),
            ink,
          ),
        if (i < friends.length)
          _Shortcut(
            friends[i].peerName,
            'Amigo',
            Text(
                friends[i].peerName.characters.take(2).toString().toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: ink)),
            () => open(() => state.selectDirectMessage(friends[i])),
            ink,
          ),
      ],
    ];

    return Container(
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: rule))),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          NixBilingualLabel(
            label: 'Atalhos',
            japanese: '近道',
            style: TextStyle(
                color: ink, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          SizedBox(
            height: 67,
            child: Row(
              children: [
                if (_before)
                  _arrow(Icons.chevron_left, 'Atalhos anteriores',
                      () => _move(-1, state.settings.reducedMotion)),
                Expanded(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _updateArrows());
                      return false;
                    },
                    child: ListView.builder(
                      key: const Key('pager_shortcuts'),
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      itemExtent: 65,
                      itemCount: shortcuts.length,
                      itemBuilder: (context, index) => shortcuts[index],
                    ),
                  ),
                ),
                if (_after)
                  _arrow(Icons.chevron_right, 'Mais atalhos',
                      () => _move(1, state.settings.reducedMotion)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, String label, VoidCallback onPressed) {
    final ink = PagerThemeScope.of(context)?.ink ?? context.watch<NixState>().settings.pagerLcdColor.inkColor;
    return SizedBox(
      width: 36,
      child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          icon: Icon(icon, color: ink)),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.name, this.kind, this.avatar, this.onTap, this.ink);

  final String name;
  final String kind;
  final Widget avatar;
  final VoidCallback onTap;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$kind · $name',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                  radius: 18,
                  backgroundColor: ink.withValues(alpha: 0.15),
                  child: avatar),
              const SizedBox(height: 3),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: MediaQuery.textScalerOf(context)
                      .clamp(maxScaleFactor: 1.4),
                  style: TextStyle(
                      color: ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
