package com.android.build;

/**
 * Shim for com.android.build.OutputFile which Flutter's Gradle plugin
 * references (import + OutputFile.ABI constant) but which is missing
 * from AGP 7.x at runtime through the Flutter plugin classloader.
 *
 * Only OutputFile.ABI is actually used by Flutter (as a string key for
 * output.getFilter()). The getFilter() call is on the variant output
 * object, not on OutputFile itself.
 */
public class OutputFile {
    public static final String ABI = "abi";
}
