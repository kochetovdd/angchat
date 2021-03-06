// Generated by CoffeeScript 1.10.0
(function() {
  var HOST, HOST_API, HOST_HTML, chatio, config;

  chatio = angular.module('chatio', ['ngRoute', 'ngCookies', 'ngAnimate', 'ngAudio', 'ngSanitize', 'ngStorage', 'ui.bootstrap', 'luegg.directives']);

  chatio.directive('actionOnFinish', function() {
    return function(scope) {
      if (scope.$last) {
        return scope.$emit('rendering finished');
      }
    };
  });

  chatio.config([
    '$locationProvider', function($locationProvider) {
      return $locationProvider.html5Mode({
        enabled: true,
        requireBase: false
      });
    }
  ]);

  HOST = window.location.hostname;

  HOST_HTML = '';

  HOST_API = '';

  config = require('../../config');

  HOST_HTML = window.location.hostname + (":" + config.ports.html);

  HOST_API = window.location.hostname + (":" + config.ports.api);

}).call(this);
