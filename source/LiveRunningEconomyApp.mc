using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Lang as Lang;

class LiveRunningEconomyApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as Lang.Array {
        return [ new LiveRunningEconomyView() ];
    }
}
