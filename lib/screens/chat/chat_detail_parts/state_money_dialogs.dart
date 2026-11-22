// 红包转账（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateMoney on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateSendInput {
  /// 转账/红包气泡点击：AI 发来的待收/待拆钱款 → 发起领取（幂等由 ChatBloc 保证）。
  VoidCallback? _moneyTapHandler(ChatMessage message) {
    if (message.type != MessageType.transfer &&
        message.type != MessageType.redPacket) {
      return null;
    }
    final meta = MoneyTransaction.fromMessageMetadata(
        message.metadata?['money'] as Map<String, dynamic>?);
    if (meta == null || meta.txId == null) return null;
    if (meta.status != MoneyStatus.pending) return null;
    if (message.isFromAI) {
      // 用户是收款方/拆包方
      return () {
        if (message.type == MessageType.redPacket) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RedPacketOpenScreen(
                amount: meta.amount,
                note: meta.note,
                senderName: message.senderName,
              ),
            ),
          ).then((_) {
            if (mounted) {
              context.read<ChatBloc>().add(ChatClaimMoney(
                    chatId: widget.session.id,
                    messageId: message.id,
                  ));
            }
          });
        } else {
          context.read<ChatBloc>().add(ChatClaimMoney(
                chatId: widget.session.id,
                messageId: message.id,
              ));
        }
      };
    }
    return null;
  }


  void _showRedPacketDialog() {
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    final balance = user?.coins ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => MoneySendDialog(
        chatId: widget.session.id,
        characterId: widget.session.aiCharacterId,
        isRedPacket: true,
        balance: balance,
      ),
    );
  }


  void _showTransferDialog() {
    // 走新版钱系统（真实扣款 + money_transactions 流水 + 新气泡卡片）
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    final balance = user?.coins ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => MoneySendDialog(
        chatId: widget.session.id,
        characterId: widget.session.aiCharacterId,
        isRedPacket: false,
        balance: balance,
      ),
    );
  }

}
