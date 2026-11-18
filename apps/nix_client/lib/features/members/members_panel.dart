import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/nix_colors.dart';
import '../../core/models/member.dart';
import '../../state/nix_state.dart';
import '../profile/peer_card_id_dialog.dart';

class MembersPanel extends StatelessWidget {
  const MembersPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final nixState = context.watch<NixState>();
    final members = nixState.members;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: NixColors.surfaceSidebar,
        border: Border(
          left: BorderSide(color: NixColors.surfaceBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text(
                  'PARTICIPANTES',
                  style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: NixColors.surfaceCardHover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${members.length}',
                    style: TextStyle(color: NixColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: NixColors.surfaceBorder),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              itemCount: members.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final member = members[index];
                return _MemberTile(member: member);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Member member;

  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => PeerCardIdDialog.showForMember(context, member),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
        children: [
          // Avatar com badge de status
          Stack(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NixColors.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: member.isSpeaking ? NixColors.accentGreen : NixColors.surfaceBorder,
                    width: member.isSpeaking ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    member.name[0],
                    style: TextStyle(color: NixColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: member.isOnline ? NixColors.accentGreen : NixColors.textDim,
                    shape: BoxShape.circle,
                    border: Border.all(color: NixColors.surfaceSidebar, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member.name,
                        style: TextStyle(
                          color: member.isOnline ? NixColors.textPrimary : NixColors.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _memberTrustBadge(member.trustLevel, member.hasCryptographicShield),
                  ],
                ),
                Text(
                  member.fingerprint.substring(0, 9),
                  style: TextStyle(
                    color: NixColors.textMuted,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _memberTrustBadge(NixTrustLevel level, bool hasShield) {
    Color dotColor = NixColors.trustLevel3Green;
    int dots = 3;
    if (level == NixTrustLevel.level1Red) {
      dotColor = NixColors.trustLevel1Red;
      dots = 1;
    } else if (level == NixTrustLevel.level2Yellow) {
      dotColor = NixColors.trustLevel2Yellow;
      dots = 2;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(
          dots,
          (i) => Container(
            width: 4.5,
            height: 4.5,
            margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ),
        if (hasShield) ...[
          const SizedBox(width: 3),
          Icon(Icons.shield, size: 10, color: dotColor),
        ],
      ],
    );
  }
}
