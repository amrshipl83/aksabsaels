// سياسة الإغلاق التلقائي ليوم العمل بعد ساعة دون زيارة جديدة.
// Pure Dart فقط: بلا أي اعتماد على Firebase حتى تبقى قابلة للاختبار دون شبكة.
//
// القاعدة:
// - عند فتح اليوم يبدأ حساب مهلة الساعة من startTime اليوم.
// - كل زيارة جديدة تعيد ضبط نقطة البداية إلى startTime تلك الزيارة.
// - المهلة تُحسب دائمًا من startTime آخر زيارة، وليس من وقت انتهائها.
// - عند انتهاء المهلة دون زيارة أحدث يُغلق اليوم، وتُغلق الزيارة المفتوحة إن وجدت.
//
// سلامة المهام القديمة: كل مهمة تحمل (workdayId + taskBasisMs) —
// وهو startTime الذي جُدولت المهمة على أساسه — وتتحقق قبل أي إغلاق من
// أحدث البيانات. أي زيارة أحدث من الأساس تعني إعادة جدولة فقط، ولا إغلاق أبدًا.

/// مهلة الخمول قبل الإغلاق التلقائي: ساعة واحدة بالمللي ثانية.
const int kWorkdayAutoCloseInactivityMs = 60 * 60 * 1000;

/// أسباب الإغلاق التلقائي المسجلة على يوم العمل / الزيارة.
abstract final class WorkdayAutoCloseReasons {
  /// لم يبدأ المندوب أي زيارة خلال الساعة الأولى من فتح اليوم.
  static const String noVisitFirstHour = 'no_visit_first_hour';

  /// مرّت ساعة من startTime آخر زيارة دون بدء زيارة أحدث.
  static const String visitInactive1h = 'visit_inactive_1h';
}

/// نص الإشعار الموحد للمندوب عند الإغلاق التلقائي.
const String kWorkdayAutoCloseNotice =
    'تم إغلاق يوم العمل لعدم تسجيل زيارات جديدة خلال ساعة. '
    'إذا كنت ستواصل العمل، يرجى بدء يوم عمل جديد وتسجيل الزيارة التالية';

/// القرار الذي تتخذه السياسة بعد فحص أحدث البيانات.
enum WorkdayAutoCloseAction {
  /// لا شيء: اليوم مغلق أصلًا، أو مهمة قديمة لا تملك قرارًا.
  noop,

  /// لا إغلاق: حدّث موعد الفحص القادم فقط.
  reschedule,

  /// أغلق يوم العمل فقط (لا توجد زيارة مفتوحة تستحق الإغلاق).
  closeWorkday,

  /// أغلق الزيارة المفتوحة أولًا ثم يوم العمل.
  closeVisitAndWorkday,
}

/// مرجع خفيف لزيارة (startTime فقط هو المهم للسياسة).
class VisitStartRef {
  final String id;
  final DateTime startTime;
  final bool isOpen;

  const VisitStartRef({
    required this.id,
    required this.startTime,
    required this.isOpen,
  });

  int get startTimeMs => startTime.millisecondsSinceEpoch;
}

/// نتيجة تقييم السياسة.
class WorkdayAutoCloseDecision {
  final WorkdayAutoCloseAction action;

  /// عند reschedule: موعد الفحص القادم.
  final DateTime? nextCheckAt;

  /// عند reschedule: الأساس الجديد (startTime الذي حُسب عليه الموعد).
  final int? nextBasisMs;

  /// عند الإغلاق: أحد WorkdayAutoCloseReasons.
  final String? reason;

  /// عند closeVisitAndWorkday: الزيارة المطلوب إغلاقها.
  final String? visitIdToClose;

  const WorkdayAutoCloseDecision._({
    required this.action,
    this.nextCheckAt,
    this.nextBasisMs,
    this.reason,
    this.visitIdToClose,
  });

  const WorkdayAutoCloseDecision.noop() : this._(action: WorkdayAutoCloseAction.noop);

  const WorkdayAutoCloseDecision.reschedule({
    required DateTime nextCheckAt,
    required int nextBasisMs,
  }) : this._(
          action: WorkdayAutoCloseAction.reschedule,
          nextCheckAt: nextCheckAt,
          nextBasisMs: nextBasisMs,
        );

  const WorkdayAutoCloseDecision.closeWorkday({required String reason})
      : this._(action: WorkdayAutoCloseAction.closeWorkday, reason: reason);

  const WorkdayAutoCloseDecision.closeVisitAndWorkday({
    required String visitIdToClose,
    required String reason,
  }) : this._(
          action: WorkdayAutoCloseAction.closeVisitAndWorkday,
          visitIdToClose: visitIdToClose,
          reason: reason,
        );
}

/// يقيّم وجوب الإغلاق التلقائي ليوم عمل واحد.
///
/// [workdayOpen]: هل حالة اليوم ما زالت open.
/// [workdayStart]: startTime اليوم (بتوقيت السيرفر عند القراءة).
/// [visits]: كل زيارات هذا اليوم (تُدمج المرتبطة بـ workdayId مع القديمة لنفس repCode).
/// [taskBasisMs]: الأساس الذي جُدولت عليه هذه المهمة الحالية
///   (startTime اليوم لأول مهمة، أو startTime آخر زيارة معروفة وقت الجدولة).
/// [now]: لحظة التنفيذ.
WorkdayAutoCloseDecision decideWorkdayAutoClose({
  required bool workdayOpen,
  required DateTime workdayStart,
  required List<VisitStartRef> visits,
  required int taskBasisMs,
  required DateTime now,
}) {
  // اليوم مغلق بالفعل: أي مهمة متأخرة لا تنفذ أي تعديل.
  if (!workdayOpen) return const WorkdayAutoCloseDecision.noop();

  final int nowMs = now.millisecondsSinceEpoch;
  final int dayStartMs = workdayStart.millisecondsSinceEpoch;

  // أحدث زيارة حسب startTime (التعادل مستحيل عمليًا؛ الأول يكفي).
  VisitStartRef? latest;
  for (final v in visits) {
    if (latest == null || v.startTimeMs > latest.startTimeMs) latest = v;
  }

  // لا توجد أي زيارة: المهلة من فتح اليوم.
  if (latest == null) {
    final dueMs = dayStartMs + kWorkdayAutoCloseInactivityMs;
    if (nowMs < dueMs) {
      return WorkdayAutoCloseDecision.reschedule(
        nextCheckAt: DateTime.fromMillisecondsSinceEpoch(dueMs),
        nextBasisMs: dayStartMs,
      );
    }
    return const WorkdayAutoCloseDecision.closeWorkday(
      reason: WorkdayAutoCloseReasons.noVisitFirstHour,
    );
  }

  // توجد زيارة أحدث من أساس هذه المهمة: مهمة قديمة — لا إغلاق أبدًا،
  // بل فحص جديد بعد ساعة من الزيارة الأحدث.
  if (latest.startTimeMs > taskBasisMs) {
    final dueMs = latest.startTimeMs + kWorkdayAutoCloseInactivityMs;
    return WorkdayAutoCloseDecision.reschedule(
      nextCheckAt: DateTime.fromMillisecondsSinceEpoch(dueMs),
      nextBasisMs: latest.startTimeMs,
    );
  }

  // لا زيارة أحدث من الأساس: المهلة من startTime آخر زيارة.
  final dueMs = latest.startTimeMs + kWorkdayAutoCloseInactivityMs;
  if (nowMs < dueMs) {
    return WorkdayAutoCloseDecision.reschedule(
      nextCheckAt: DateTime.fromMillisecondsSinceEpoch(dueMs),
      nextBasisMs: latest.startTimeMs,
    );
  }

  // انتهت المهلة: أغلق الزيارة إن كانت ما زالت مفتوحة، ثم اليوم.
  if (latest.isOpen) {
    return WorkdayAutoCloseDecision.closeVisitAndWorkday(
      visitIdToClose: latest.id,
      reason: WorkdayAutoCloseReasons.visitInactive1h,
    );
  }
  return const WorkdayAutoCloseDecision.closeWorkday(
    reason: WorkdayAutoCloseReasons.visitInactive1h,
  );
}
