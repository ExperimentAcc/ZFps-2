// AIDL interface for the Shizuku user service.
// The implementation (UserService.kt) runs inside a Shizuku-privileged
// process (uid = shell) so it can read kernel thermal zones, /proc,
// SurfaceFlinger and other restricted interfaces.
package com.zsdev.fpsmonitor;

interface IUserService {

    // Reserved destroy method defined by the Shizuku server
    void destroy() = 16777114;

    // Run `sh -c <command>` as the shell user and return stdout+stderr
    String exec(String command) = 1;
}
