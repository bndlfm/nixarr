{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "anchorr";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "nairdahh";
    repo = "Anchorr";
    rev = "v${version}";
    hash = "sha256-8xlablHtBtJuOgm/7hl4XWmyWYD+fE7L9igRECErDX4=";
  };

  npmDepsHash = "sha256-YXPLHloxRci8PIDB5g+myxP36JFhQ2M54hQC86+1mMY=";

  # Anchorr expects to find some files in its working directory
  # The web interface and other assets need to be available.
  # Most Node.js apps need some post-install cleanup or adjustment.
  
  makeCacheWritable = true;
  dontNpmBuild = true;

  meta = with lib; {
    description = "Discord bot for media requests via Jellyseerr and notifications for Jellyfin";
    homepage = "https://github.com/nairdahh/Anchorr";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.linux;
  };
}
