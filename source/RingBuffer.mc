import Toybox.Lang;

// Fixed-capacity circular buffer. No allocation after construction.
class RingBuffer {

    private var _data as Array<Float>;
    private var _capacity as Number;
    private var _count as Number;
    private var _writeIndex as Number;

    function initialize(capacity as Number) {
        _capacity = capacity;
        _data = new [capacity];
        _count = 0;
        _writeIndex = 0;
    }

    function push(value as Float) as Void {
        _data[_writeIndex] = value;
        _writeIndex = (_writeIndex + 1) % _capacity;
        if (_count < _capacity) {
            _count++;
        }
    }

    function reset() as Void {
        _count = 0;
        _writeIndex = 0;
    }

    function size() as Number {
        return _count;
    }

    // index 0 = oldest sample, size()-1 = newest
    function get(index as Number) as Float {
        var start = (_writeIndex - _count + _capacity) % _capacity;
        return _data[(start + index) % _capacity];
    }

    function minValue() as Float? {
        if (_count == 0) {
            return null;
        }
        var m = get(0);
        for (var i = 1; i < _count; i++) {
            var v = get(i);
            if (v < m) {
                m = v;
            }
        }
        return m;
    }

    function maxValue() as Float? {
        if (_count == 0) {
            return null;
        }
        var m = get(0);
        for (var i = 1; i < _count; i++) {
            var v = get(i);
            if (v > m) {
                m = v;
            }
        }
        return m;
    }
}
