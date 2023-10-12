![myQ](images/header.png)

---

# <span style="color:#5EB5E6">Overview</span>

> DISCLAIMER: This software is neither affiliated with nor endorsed by either
> Control4 or Chamberlain.

Easily integrate myQ garage doors and gates into Control4 without the need of
additional hardware or manual wiring to the controller. This driver connects to
a myQ cloud account, discovers the devices and makes them available to the
Control4 project.

# <span style="color:#5EB5E6">System requirements</span>

- Control4 OS 3.3+

# <span style="color:#5EB5E6">Features</span>

- Supports all known myQ compatible garage doors and gates
- Supports shared account devices
- Automatic updates
- Easy and maintenance free installation

# <span style="color:#5EB5E6">Driver Setup</span>

See the "Driver Setup" defined in the `myq_controller.c4z` driver.

## Driver Properties

### Driver Settings

##### Driver Version (read only)

Displays the current version of the driver.

##### Log Level [ Fatal | Error | Warning | **_Info_** | Debug | Trace | Ultra ]

Sets the logging level. Default is `Info`.

##### Log Mode [ **_Off_** | Print | Log | Print and Log ]

Sets the logging mode. Default is `Off`.

### Device Settings

##### Device Name (read only)

Displays the myQ device name.

##### Device Type (read only)

Displays the myQ device type (e.g. `Garage Door Opener`, `Gate`, etc.).

##### Device Status (read only)

Displays the myQ device state (e.g. `OPEN`, `CLOSED`, etc.).

##### Auto-Rename

Sets the auto-rename functionality. If `Yes`, the driver will be renamed based
on the name of the device in myQ.

##### Still Open Time (s)

Sets the amount of time before firing the `Still Open` event when the device
transitions to a state that is not `CLOSED`. Setting this to `0` disables the
feature.

##### Opened LED Color

Color of attached keypad buttons on `OPENED` state.

##### Closed LED Color

Color of attached keypad buttons on `CLOSED` state.

##### Partial Open LED Color

Color of attached keypad buttons on `OPENING` and `CLOSING` states.

##### Inactive LED Color

Color of attached Open/Close keypad buttons when not active (i.e. 'Open' button
link when closed and vice-versa).

##### Unknown LED Color

Color of attached keypad buttons on `UNKNOWN` state.

## Driver Actions

#### Open

Trigger the device to open.

#### Close

Trigger the device to close.

#### Reset LED Colors to Project Defaults

Resets the LED colors to the project's defaults.

## Driver Events

#### Opened

Fired when the device transitions to the `OPEN` state.

#### Closed

Fired when the device transitions to the `CLOSED` state.

#### Partial

Fired when the device transitions to the `OPENING` or `CLOSING` states.

#### Unknown

Fired when the device transitions to the `UNKNOWN` state.

#### Still Open

Fired when the device remains open longer than the duration defined by the
[`Still Open Time (s)`](#still-open-time-s) property.

# <span style="color:#5EB5E6">Support</span>

If you have any questions or issues integrating this driver with Control4 you
can file an issue on GitHub:

https://github.com/black-ops-drivers/control4-myq/issues/new

# <span style="color:#5EB5E6">Changelog</span>

[//]: # "## v[Version] - YYY-MM-DD"
[//]: # "### Added"
[//]: # "- Added"
[//]: # "### Fixed"
[//]: # "- Fixed"
[//]: # "### Changed"
[//]: # "- Changed"
[//]: # "### Removed"
[//]: # "- Removed"

## v20231012 - 2023-10-12

### Fixed

- Fixed an issue where authentication would fail due to myQ API changes.

## v20230912 - 2023-09-12

### Fixed

- Fixed an issue where automatic updates were never performed. **_NOTE:_** All
  versions prior to this will need to be manually updated.

## v20230908 - 2023-09-08

### Fixed

- Fixed an issue where authentication would fail due to myQ API changes.

## v20230902 - 2023-09-02

### Changed

- Changed polling period to be more frequent for a short time after commanding a
  gate or garage door.
- Changed the open/close pending icons to use the partially open gate/garage
  door icon.

## v20230829 - 2023-08-29

### Added

- Added `Still Open` event for the device, configured by the
  `Still Open Time (s)` property.

## v20230823 - 2023-08-23

### Fixed

- Fixed login issue where the wrong response was used to determine if the
  credentials were valid.

## v20230822 - 2023-08-22

### Added

- Initial release.
