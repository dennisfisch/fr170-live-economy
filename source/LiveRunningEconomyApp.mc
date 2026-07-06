using Toybox.Application as App;
using Toybox.WatchUi as Ui;
import Toybox.Lang;

class LiveRunningEconomyApp extends App.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new LiveRunningEconomyView() ];
    }
}
