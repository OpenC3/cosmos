---
title: XTCE Support
description: XTCE Command and Telemetry Definition Standard
sidebar_custom_props:
  myEmoji: 😵
---

COSMOS has support for the [XTCE Command and Telemetry Definition Standard](https://www.omg.org/xtce/index.htm). This is an open standard designed to allow command and telemetry definitions to be transferred between different ground systems. COSMOS can run directly using the .xtce files, or can convert them into the COSMOS configuration file format.

## XTCE Version

COSMOS exports **XTCE 1.2** (namespace `http://www.omg.org/spec/XTCE/20180204`), and generated files validate against the OMG `SpaceSystem.xsd` schema they declare. Both the Ruby and Python exporters produce the same version.

Importing is more permissive: files declaring XTCE 1.0, 1.1 or 1.2 are all accepted. Where the versions differ, COSMOS accepts both spellings, for example an `ArrayArgumentRefEntry` may use `argumentRef` (1.2) or `parameterRef` (1.0/1.1 and files exported by COSMOS 7.2 and earlier), and byte order may be given as a `ByteOrderList` (1.0/1.1) or the `byteOrder` attribute (1.2).

## Running COSMOS using an .xtce definition file

A single .xtce file containing the command and telemetry definitions for a target can be used in place of the normal COSMOS command and telemetry definition files. Simply place the target's .xtce file in the target's cmd_tlm folder and COSMOS will use it for the command and telemetry definitions.

## Converting a .xtce file into a COSMOS configuration

Use the following command to convert a .xtce file into COSMOS configuration files. The converted configuration files will be placed into a target folder in the given output directory.

```
openc3.sh cli xtce_converter --import <xtce_filename> --output <output_dir>
```

## Converting a COSMOS Configuration to XTCE

Use the following command to convert your openc3 plugin into .xtce files, one per target. The converted .xtce files will be placed into a target folder in the given output directory.

```
openc3.sh cli xtce_converter --plugin <plugin.gem> --output <output_dir>
```

On Windows use `openc3.bat` in place of `openc3.sh`.

## High-level Overview of Current Support

1.  Integer, Float, Enumerated, String and Binary Parameter/Argument Types are supported
1.  Boolean Parameter/Argument Types can be imported (they are exported as Enumerated)
1.  Array Parameter/Argument Types are supported (one dimension only)
1.  All DataEncodings are supported
1.  Telemetry and Commands are supported
1.  Packet Identification is supported
1.  States are supported
1.  Units are supported
1.  PolynomialCalibrators are supported
1.  Limits are supported via DefaultAlarm / StaticAlarmRanges
1.  Command argument ranges are supported via ValidRange
1.  Big and little endian items are supported
1.  Only one SpaceSystem per .xtce file
1.  Packets with gaps between items are supported: each entry is located with a
    LocationInContainerInBits relative to the container start, the container end,
    or the previous entry

## Supported Elements and Attributes

The following elements and associated attributes are currently supported. Unless
noted otherwise, an element is both read when importing a .xtce file and written
when exporting one. Two annotations appear in the list:

- **import only** - the element is understood when reading a .xtce file, but is
  never produced by the COSMOS exporter because COSMOS has no equivalent concept
  to write out.
- **written on export, ignored on import** - the COSMOS exporter emits the
  element so the generated file is complete and schema valid, but the importer
  does not act on it, so the information it carries is lost on a round trip.

- SpaceSystem
- TelemetryMetaData
- CommandMetaData
- ParameterTypeSet
- EnumerationList
- ParameterSet
- ContainerSet
- EntryList
- DefaultCalibrator
- DefaultAlarm
- RestrictionCriteria
- ComparisonList
- MetaCommandSet
- ArgumentTypeSet
- ArgumentList
- ArgumentAssignmentList
- EnumeratedParameterType
- EnumeratedArgumentType
- IntegerParameterType
- IntegerArgumentType
- FloatParameterType
- FloatArgumentType
- StringParameterType
- StringArgumentType
- BinaryParameterType
- BinaryArgumentType
- BooleanParameterType (import only)
- BooleanArgumentType (import only)
- ArrayParameterType
- ArrayArgumentType
- DimensionList
- Dimension
- StartingIndex
- EndingIndex
- IntegerDataEncoding
- FloatDataEncoding
- StringDataEncoding
- BinaryDataEncoding
- ByteOrderList (XTCE 1.0 / 1.1 import only, the 1.2 byteOrder attribute is used on export)
- Byte
- SizeInBits
- Fixed
- FixedValue
- TerminationChar (written on export, ignored on import)
- UnitSet
- Unit
- PolynomialCalibrator
- Term
- StaticAlarmRanges
- WarningRange
- CriticalRange
- ValidRange
- ValidRangeSet
- Enumeration
- Parameter
- Argument
- ParameterProperties
- SequenceContainer
- BaseContainer
- LocationInContainerInBits
- LongDescription
- ParameterRefEntry
- ArgumentRefEntry
- ArrayParameterRefEntry
- ArrayArgumentRefEntry
- ContainerRefEntry (import only)
- BaseMetaCommand
- Comparison
- MetaCommand
- CommandContainer
- ArgumentAssignment

## Ignored Elements

The following elements are recognized but have no effect on the resulting
configuration:

- Header
- AliasSet
- Alias
- ReferenceTime
- Epoch
- AncillaryDataSet
- AncillaryData
- ErrorDetectCorrect - the item is read as an unsigned integer and the CRC is not calculated

## Unsupported Elements

Any elements not listed above are currently unsupported. Near term support for the following elements and features are planned and priority will be determined by user requests.

- SplineCalibrator
- AbsoluteTimeParameterType / AbsoluteTimeArgumentType and the relative time types
- Multi-dimensional arrays
- `nextEntry` entry offsets (`containerStart`, `containerEnd` and `previousEntry` are supported)
- Output to the XUSP standard
- Additional Data Types

If there is a particular element or feature you need supported please submit a ticket on Github.
