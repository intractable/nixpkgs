{ lowPrio, newScope, stdenv, targetPlatform, cmake, libstdcxxHook
, libxml2, python2, isl, fetchurl, overrideCC, wrapCCWith
, darwin
, buildLlvmTools # tools, but from the previous stage, for cross
, targetLlvmLibraries # libraries, but from the next stage, for cross
}:

let
  release_version = "6.0.0";
  version = release_version; # differentiating these is important for rc's

  fetch = name: sha256: fetchurl {
    url = "http://releases.llvm.org/${release_version}/${name}-${version}.src.tar.xz";
    inherit sha256;
  };

  compiler-rt_src = fetch "compiler-rt" "16m7rvh3w6vq10iwkjrr1nn293djld3xm62l5zasisaprx117k6h";
  clang-tools-extra_src = fetch "clang-tools-extra" "1ll9v6r29xfdiywbn9iss49ad39ah3fk91wiv0sr6k6k9i544fq5";

  # Add man output without introducing extra dependencies.
  overrideManOutput = drv:
    let drv-manpages = drv.override { enableManpages = true; }; in
    drv // { man = drv-manpages.out; /*outputs = drv.outputs ++ ["man"];*/ };

  tools = let
    callPackage = newScope (tools // { inherit stdenv cmake libxml2 python2 isl release_version version fetch; });
  in {

    llvm = overrideManOutput (callPackage ./llvm.nix {
      inherit compiler-rt_src;
      inherit (targetLlvmLibraries) libcxxabi;
    });
    clang-unwrapped = overrideManOutput (callPackage ./clang {
      inherit clang-tools-extra_src;
    });

    libclang = tools.clang-unwrapped.lib;
    llvm-manpages = lowPrio tools.llvm.man;
    clang-manpages = lowPrio tools.clang-unwrapped.man;

    clang = if stdenv.cc.isGNU then tools.libstdcxxClang else tools.libcxxClang;

    libstdcxxClang = wrapCCWith {
      cc = tools.clang-unwrapped;
      extraPackages = [ libstdcxxHook ];
    };

    libcxxClang = wrapCCWith {
      cc = tools.clang-unwrapped;
      extraPackages = [ targetLlvmLibraries.libcxx targetLlvmLibraries.libcxxabi ];
    };

    lld = callPackage ./lld.nix {};

    lldb = callPackage ./lldb.nix {};
  };

  libraries = let
    callPackage = newScope (libraries // buildLlvmTools // { inherit stdenv cmake libxml2 python2 isl release_version version fetch; });
  in {

    stdenv = overrideCC stdenv buildLlvmTools.clang;

    libcxxStdenv = overrideCC stdenv buildLlvmTools.libcxxClang;

    libcxx = callPackage ./libc++ {};

    libcxxabi = callPackage ./libc++abi.nix {};

    openmp = callPackage ./openmp.nix {};
  };

in { inherit tools libraries; } // libraries // tools
