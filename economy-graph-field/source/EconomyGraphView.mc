using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Activity as Activity;
using Toybox.Application as App;
import Toybox.Lang;

const GRAPH_METRIC_POWER_HR = 0;
const GRAPH_METRIC_EF = 1;
const RING_CAPACITY = 30;
const MOVING_SPEED_THRESHOLD = 0.5; // m/s; below this, HR/power ratios are too noisy to be meaningful
const SMOOTHING_ALPHA = 0.33; // EMA over ~3 samples at the ~1 Hz compute() rate
const FULL_SCREEN_MIN_DIM = 200; // px; below this we're in a small multi-field slot, degrade to numbers only

class LiveRunningEconomyView extends Ui.DataField {

    private var _ring as RingBuffer;
    private var _graphMetric as Number;
    private var _gradeAdjustEnabled as Boolean;

    private var _smoothedPowerHr as Float?;
    private var _smoothedEf as Float?;

    private var _splitPowerHrSum as Float = 0.0;
    private var _splitPowerHrCount as Number = 0;
    private var _splitEfSum as Float = 0.0;
    private var _splitEfCount as Number = 0;

    private var _prevAltitude as Float?;
    private var _prevDistance as Float?;

    function initialize() {
        DataField.initialize();
        _ring = new RingBuffer(RING_CAPACITY);
        _graphMetric = GRAPH_METRIC_POWER_HR;
        _gradeAdjustEnabled = false;
        loadSettings();
        resetSplit();
    }

    function loadSettings() as Void {
        var metric = App.Properties.getValue("GraphMetric");
        if (metric != null) {
            _graphMetric = metric;
        }
        var gradeAdjust = App.Properties.getValue("GradeAdjustEnabled");
        if (gradeAdjust != null) {
            _gradeAdjustEnabled = gradeAdjust;
        }
    }

    function onSettingsChanged() as Void {
        loadSettings();
        _ring.reset();
    }

    function resetSplit() as Void {
        _splitPowerHrSum = 0.0;
        _splitPowerHrCount = 0;
        _splitEfSum = 0.0;
        _splitEfCount = 0;
    }

    function onTimerLap() as Void {
        resetSplit();
    }

    function onTimerReset() as Void {
        resetSplit();
        _ring.reset();
        _smoothedPowerHr = null;
        _smoothedEf = null;
        _prevAltitude = null;
        _prevDistance = null;
    }

    function compute(info as Activity.Info) as Void {
        // Optional Activity.Info fields must be `has`-guarded: an unguarded access throws
        // "Symbol Not Found" at runtime on devices/firmware where the field isn't populated.
        var hr = (info has :currentHeartRate) ? info.currentHeartRate : null;
        var power = (info has :currentPower) ? info.currentPower : null;
        var speed = (info has :currentSpeed) ? info.currentSpeed : null;

        if (hr == null || hr <= 0 || speed == null || speed <= MOVING_SPEED_THRESHOLD) {
            return;
        }

        var ef = (speed.toFloat() / hr.toFloat()) * 1000.0;
        if (_gradeAdjustEnabled) {
            ef = applyGradeAdjustment(ef, info);
        }
        _smoothedEf = smooth(_smoothedEf, ef);
        _splitEfSum += ef;
        _splitEfCount++;

        var powerHr = null;
        if (power != null) {
            powerHr = power.toFloat() / hr.toFloat();
            _smoothedPowerHr = smooth(_smoothedPowerHr, powerHr);
            _splitPowerHrSum += powerHr;
            _splitPowerHrCount++;
        }

        var graphValue = (_graphMetric == GRAPH_METRIC_EF) ? ef : powerHr;
        if (graphValue != null) {
            _ring.push(graphValue);
        }
    }

    private function smooth(prev as Float?, sample as Float) as Float {
        if (prev == null) {
            return sample;
        }
        return prev + SMOOTHING_ALPHA * (sample - prev);
    }

    // Rough grade correction: speed *= 1 + 3*grade, clamped to keep GPS/baro glitches from spiking the display.
    private function applyGradeAdjustment(ef as Float, info as Activity.Info) as Float {
        var altitude = (info has :altitude) ? info.altitude : null;
        var distance = (info has :elapsedDistance) ? info.elapsedDistance : null;
        var adjusted = ef;

        if (altitude != null && distance != null && _prevAltitude != null && _prevDistance != null) {
            var dDist = distance - _prevDistance;
            if (dDist >= 1.0) {
                var grade = (altitude - _prevAltitude) / dDist;
                var factor = 1.0 + (grade * 3.0);
                if (factor < 0.5) {
                    factor = 0.5;
                }
                if (factor > 2.0) {
                    factor = 2.0;
                }
                adjusted = ef * factor;
            }
        }

        if (altitude != null && distance != null) {
            _prevAltitude = altitude;
            _prevDistance = distance;
        }

        return adjusted;
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
        dc.clear();

        if (width < FULL_SCREEN_MIN_DIM || height < FULL_SCREEN_MIN_DIM) {
            drawCompact(dc, width, height);
            return;
        }

        var nowHeight = (height * 0.36).toNumber();
        var splitHeight = (height * 0.30).toNumber();
        drawRow(dc, 0, nowHeight, width, _smoothedEf, _smoothedPowerHr, Gfx.FONT_NUMBER_MEDIUM, "NOW");
        drawRow(dc, nowHeight, splitHeight, width, splitEf(), splitPowerHr(), Gfx.FONT_NUMBER_MILD, "SPLIT");
        drawGraph(dc, nowHeight + splitHeight, height - nowHeight - splitHeight, width);
    }

    private function drawCompact(dc as Gfx.Dc, width as Number, height as Number) as Void {
        var y1 = height * 0.25;
        var y2 = height * 0.65;
        dc.drawText(width / 2, y1, Gfx.FONT_TINY, "EF " + formatValue(_smoothedEf), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 2, y2, Gfx.FONT_TINY, "P/HR " + formatValue(_smoothedPowerHr), Gfx.TEXT_JUSTIFY_CENTER);
    }

    private function drawRow(dc as Gfx.Dc, y as Number, rowHeight as Number, width as Number, efValue as Float?, powerHrValue as Float?, font as Gfx.FontDefinition, label as String) as Void {
        var titleFont = Gfx.FONT_XTINY;
        var titleH = dc.getFontHeight(titleFont);
        var metricLabelY = y + titleH + 2;
        var valueY = metricLabelY + titleH + 2;

        dc.drawText(width / 2, y, titleFont, label, Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 4, metricLabelY, titleFont, "EF", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width * 3 / 4, metricLabelY, titleFont, "P/HR", Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width / 4, valueY, font, formatValue(efValue), Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width * 3 / 4, valueY, font, formatValue(powerHrValue), Gfx.TEXT_JUSTIFY_CENTER);
    }

    private function drawGraph(dc as Gfx.Dc, y as Number, areaHeight as Number, width as Number) as Void {
        var count = _ring.size();
        var label = (_graphMetric == GRAPH_METRIC_EF) ? "EF (30s)" : "P/HR (30s)";
        dc.drawText(width / 2, y + 2, Gfx.FONT_XTINY, label, Gfx.TEXT_JUSTIFY_CENTER);

        if (count < 2) {
            dc.drawText(width / 2, y + areaHeight / 2, Gfx.FONT_XTINY, "collecting...", Gfx.TEXT_JUSTIFY_CENTER);
            return;
        }

        var minV = _ring.minValue();
        var maxV = _ring.maxValue();
        var range = maxV - minV;
        if (range < 0.01) {
            range = 0.01;
        }

        var plotTop = y + 16;
        var plotHeight = areaHeight - 20;
        var plotLeft = 8;
        var plotWidth = width - 16;

        var prevX = 0;
        var prevY = 0;
        for (var i = 0; i < count; i++) {
            var v = _ring.get(i);
            var px = plotLeft + (plotWidth * i) / (RING_CAPACITY - 1);
            var py = plotTop + plotHeight - (((v - minV) / range) * plotHeight);
            if (i > 0) {
                dc.drawLine(prevX, prevY, px, py);
            }
            prevX = px;
            prevY = py;
        }

        dc.drawText(plotLeft, y + areaHeight - 12, Gfx.FONT_XTINY, "min " + formatValue(minV), Gfx.TEXT_JUSTIFY_LEFT);
        dc.drawText(width - plotLeft, y + areaHeight - 12, Gfx.FONT_XTINY, "max " + formatValue(maxV), Gfx.TEXT_JUSTIFY_RIGHT);
    }

    private function splitEf() as Float? {
        return (_splitEfCount > 0) ? (_splitEfSum / _splitEfCount) : null;
    }

    private function splitPowerHr() as Float? {
        return (_splitPowerHrCount > 0) ? (_splitPowerHrSum / _splitPowerHrCount) : null;
    }

    private function formatValue(value as Float?) as String {
        if (value == null) {
            return "--";
        }
        return value.format("%.1f");
    }
}
