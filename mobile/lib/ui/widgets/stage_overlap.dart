import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Üst sahne ([stage]) ile altındaki içeriği ([body]) dikeyde [overlap] kadar üst üste bindirir: gövdenin ilk kartı
/// sahnenin alt kenarına biner. (`Column` negatif aralığı kabul etmez; bu widget aynı işi yerleşim düzeyinde yapar,
/// bu yüzden gövdeden sonraki içerik de doğru yere oturur.) Sahne önce, gövde üstüne çizilir; dokunma gövdeden başlar.
class StageOverlap extends MultiChildRenderObjectWidget {
  StageOverlap({super.key, required this.overlap, required Widget stage, required Widget body}) : super(children: [stage, body]);

  final double overlap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStageOverlap(overlap);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderStageOverlap).overlap = overlap;
  }
}

class _StageParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderStageOverlap extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _StageParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _StageParentData> {
  _RenderStageOverlap(this._overlap);

  double _overlap;
  set overlap(double v) {
    if (v == _overlap) return;
    _overlap = v;
    markNeedsLayout();
  }

  RenderBox get _stage => firstChild!;
  RenderBox get _body => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StageParentData) child.parentData = _StageParentData();
  }

  BoxConstraints _tight(BoxConstraints c) => BoxConstraints(minWidth: c.maxWidth, maxWidth: c.maxWidth);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = _tight(constraints);
    final stage = _stage.getDryLayout(c);
    final body = _body.getDryLayout(c);
    return constraints.constrain(Size(c.maxWidth, math.max(0, stage.height - _overlap) + body.height));
  }

  @override
  void performLayout() {
    final c = _tight(constraints);
    _stage.layout(c, parentUsesSize: true);
    _body.layout(c, parentUsesSize: true);
    final top = math.max(0.0, _stage.size.height - _overlap);
    (_stage.parentData! as _StageParentData).offset = Offset.zero;
    (_body.parentData! as _StageParentData).offset = Offset(0, top);
    size = constraints.constrain(Size(c.maxWidth, top + _body.size.height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(0, _stage.getMinIntrinsicHeight(width) - _overlap) + _body.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(0, _stage.getMaxIntrinsicHeight(width) - _overlap) + _body.getMaxIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(_stage.getMinIntrinsicWidth(height), _body.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(_stage.getMaxIntrinsicWidth(height), _body.getMaxIntrinsicWidth(height));

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
