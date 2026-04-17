{ pkgs, lib, config, inputs, ... }:

{
  packages = [
    pkgs.elmPackages.elm-format
    pkgs.elmPackages.elm-test
    pkgs.elmPackages.elm-review
  ];

  languages.javascript = {
    enable = true;
    npm.enable = true;
  };

  languages.elm.enable = true;
}
