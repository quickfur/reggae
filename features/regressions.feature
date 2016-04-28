@regression
Feature: Regressions
  As a reggae developer
  I want to reproduce bugs with regression tests
  So that bugs are not reintroduced

  @ninja
  Scenario: Github issue 14: $builddir not expanded
    Given a file named "project/reggaefile.d" with:
      """
      import reggae;

      enum ao = objectFile(SourceFile("a.c"));
      enum liba = Target("$builddir/liba.a", "ar rcs $out $in", [ao]);
      mixin build!(liba);
      """
    And a file named "project/a.c" with:
      """
      """
    When I successfully run `reggae -b ninja project`
    Then I successfully run `ninja`

  @ninja
  Scenario: Github issue 12: Can't set executable as a dependency
    Given a file named "project/reggaefile.d" with:
      """
      import reggae;
      alias app = scriptlike!(App(SourceFileName("src/main.d"), BinaryFileName("$builddir/myapp")),
                              Flags("-g -debug"),
                              ImportPaths(["/path/to/imports"])
                              );
      alias code_gen = target!("out.c", "./myapp $in $out", target!"in.txt", app);
      mixin build!(code_gen);
      """
    And a file named "project/src/main.d" with:
      """
      import std.stdio;
      import std.algorithm;
      import std.conv;
      void main(string[] args) {
          auto inFileName = args[1];
          auto outFileName = args[2];
          auto lines = File(inFileName).byLine.
                                        map!(a => a.to!string).
                                        map!(a => a ~ ` ` ~ a);
          auto outFile = File(outFileName, `w`);
          foreach(line; lines) outFile.writeln(line);
      }
      """
    And a file named "project/in.txt" with:
      """
      foo
      bar
      baz
      """
    When I successfully run `reggae -b ninja project`
    And I successfully run `ninja`
    And I successfully run `cat out.c`
    Then the output should contain:
     """
     foo foo
     bar bar
     baz baz
     """

  @ninja
  Scenario: Github issue 10: dubConfigurationTarget doesn't work for unittest builds
    Given a file named "project/dub.json" with:
      """
      {
          "name": "dubproj",
          "configurations": [
              { "name": "executable"},
              { "name": "unittest"}
          ]
      }
      """
    And a file named "project/reggaefile.d" with:
      """
      import reggae;
      alias ut = dubConfigurationTarget!(ExeName(`ut`),
                                         Configuration(`unittest`),
                                         Flags(`-g -debug -cov`));
      mixin build!ut;
      """
    And a file named "project/source/src.d" with:
      """
      unittest { static assert(false, `oopsie`); }
      int add(int i, int j) { return i + j; }
      """
    And a file named "project/source/main.d" with:
      """
      import src;
      void main() {}
      """
    Given I successfully run `reggae -b ninja project`
    When I run `ninja`
    Then it should fail with:
      """
      oopsie
      """

  @ninja
  Scenario: Using . as the project should work
    Given a file named "reggaefile.d" with:
    """
    import reggae;
    mixin build!(scriptlike!(App(SourceFileName(`app.d`))));
    """
    And a file named "app.d" with:
    """
    import std.stdio;
    void main() { writeln(`Hello world!`); }
    """
    When I successfully run `reggae -b ninja .`
    And I successfully run `ninja`
    And I successfully run `./app`
    Then the output should contain:
    """
    Hello world!
    """
