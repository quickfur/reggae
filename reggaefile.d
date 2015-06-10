import reggae;

version(minimal) {

    //flags have to name $project explicitly since these are low-level build definitions,
    //not the high level ones that do this automatically
    enum flags = "-version=minimal -I$project/src -I$project/payload -J$project/payload/reggae";
    enum srcs = [Target("src/reggae/reggae_main.d"), Target("src/reggae/options.d"),
                Target("payload/reggae/types.d"), Target("payload/reggae/build.d"),
                Target("payload/reggae/config.d"), Target("payload/reggae/rules/common.d"),
                Target("payload/reggae/rules/defaults.d")];
    enum cmd = "dmd -of$out " ~ flags ~ " $in";
    enum main = Target("bin/reggae", cmd, srcs);
    mixin build!(main);

} else {
    //fully feature build

    //the actual reggae binary
    //could also be dubConfigurationTarget(ExeName("reggae"), Configuration("executable"))
    alias main = dubDefaultTargetWithFlags!(Flags("-g -debug"));

    //the unit test binary
    alias ut = dubConfigurationTarget!(ExeName("ut"),
                                       Configuration("unittest"),
                                       Flags("-g -debug -cov"));

    mixin build!(main, ut);
}
