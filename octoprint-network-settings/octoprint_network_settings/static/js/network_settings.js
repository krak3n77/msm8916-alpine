$(function () {
    function NetworkSettingsViewModel() {
        var self = this;

        self.state = ko.observable("loading");
        self.activeConnection = ko.observable("");
        self.ssid = ko.observable("");
        self.password = ko.observable("");
        self.mode = ko.observable("auto");
        self.address = ko.observable("");
        self.gateway = ko.observable("");
        self.dns = ko.observable("");
        self.saving = ko.observable(false);
        self.message = ko.observable("");
        self.messageIsError = ko.observable(false);

        self.isStatic = ko.pureComputed(function () {
            return self.mode() === "manual";
        });

        self.setMessage = function (text, isError) {
            self.message(text || "");
            self.messageIsError(!!isError);
        };

        self.load = function (keepMessage) {
            if (!keepMessage) {
                self.setMessage("", false);
            }
            $.getJSON(API_BASEURL + "plugin/network_settings/status")
                .done(function (data) {
                    self.state(data.state || "unknown");
                    self.activeConnection(data.connection || "");
                    self.ssid(data.ssid || data.connection || "");
                    self.mode(data.ipv4_method === "manual" ? "manual" : "auto");
                    self.address(data.address || "");
                    self.gateway(data.gateway || "");
                    self.dns(data.dns || "");
                    self.password("");
                    if (data.config_error && data.state !== "connected") {
                        self.setMessage(data.config_error, false);
                    }
                })
                .fail(function (xhr) {
                    var data = xhr.responseJSON || {};
                    self.setMessage(data.error || "Failed to load network settings", true);
                });
        };

        self.save = function () {
            self.saving(true);
            self.setMessage("", false);

            $.ajax({
                url: API_BASEURL + "plugin/network_settings/save",
                type: "POST",
                contentType: "application/json; charset=UTF-8",
                dataType: "json",
                data: JSON.stringify({
                    ssid: self.ssid(),
                    password: self.password(),
                    mode: self.mode(),
                    address: self.address(),
                    gateway: self.gateway(),
                    dns: self.dns()
                })
            })
                .done(function () {
                    self.setMessage("Saved. Changes are staged; apply UI comes later.", false);
                    self.load(true);
                })
                .fail(function (xhr) {
                    var data = xhr.responseJSON || {};
                    self.setMessage(data.error || "Save failed", true);
                })
                .always(function () {
                    self.saving(false);
                });
        };

        self.onSettingsShown = function () {
            self.load();
        };
    }

    OCTOPRINT_VIEWMODELS.push({
        construct: NetworkSettingsViewModel,
        dependencies: [],
        elements: ["#settings_plugin_network_settings"]
    });
});
