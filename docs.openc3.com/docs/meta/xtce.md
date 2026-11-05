---
title: XTCE Support
description: XTCE Command and Telemetry Definition Standard
sidebar_custom_props:
  myEmoji: 😵
---

COSMOS has support for the [XTCE Command and Telemetry Definition Standard](https://www.omg.org/xtce/index.htm). This is an open standard designed to allow command and telemetry definitions to be transferred between different ground systems. COSMOS can run directly using the .xtce files, or can convert them into the COSMOS configuration file format.

## XTCE Version

COSMOS exports **XTCE 1.2** (namespace `http://www.omg.org/spec/XTCE/20180204`), and generated files validate against the OMG `SpaceSystem.xsd` schema they declare. Both the Ruby and Python exporters produce the same version.

Importing is more permissive: files declaring XTCE 1.0, 1.1 or 1.2 are all accepted. Where the versions differ, COSMOS accepts both spellings, for example an `ArrayArgumentRefEntry` may use `argumentRef` (1.2) or `parameterRef` (1.0/1.1 and files exported by COSMOS 7.2 and earlier), and byte order may be given as a `ByteOrderList` (1.0/1.1) or the `byteOrder` attribute (1.2). A `StringParameterType` / `StringArgumentType` `initialValue` may be quoted (COSMOS 7.2 and earlier) or unquoted (what COSMOS writes now, and what the standard calls for).

Files exported by COSMOS 7.2 and earlier import here. The reverse is not guaranteed: two of the schema conformance fixes in this version are not understood by a 7.2 importer, which expects `parameterRef` on an `ArrayArgumentRefEntry` (it reports `parameterRef not found`) and reads a binary `initialValue` as a literal string unless it is `0x` prefixed (so a `hexBinary` default is silently taken as text). Import an .xtce file with an older COSMOS only if it has no array command arguments and no binary defaults.

## How Packets Are Structured on Export

A packet with ID items is exported as a pair: an abstract container holding the entries, and a concrete container that inherits from it and adds the ID comparisons. The comparisons have to live in a `RestrictionCriteria`, which only exists on a `BaseContainer`, so there has to be something to inherit from.

- Telemetry: `<SequenceContainer name="PKT_Base" abstract="true">` with the `EntryList`, then `<SequenceContainer name="PKT">` with a `BaseContainer` referencing `PKT_Base` and the `RestrictionCriteria` inside it.
- Commands: `<MetaCommand name="CMD_Base" abstract="true">` with the `ArgumentList` and a `CommandContainer` named `CMD_CommandsBase`, then `<MetaCommand name="CMD">` with a `BaseMetaCommand` and a `CommandContainer` whose `BaseContainer` carries the `RestrictionCriteria`.

A packet with no ID items is a single container holding its entries, with no `BaseContainer` at all.

## Running COSMOS using an .xtce definition file

A single .xtce file containing the command and telemetry definitions for a target can be used in place of the normal COSMOS command and telemetry definition files. Simply place the target's .xtce file in the target's cmd_tlm folder and COSMOS will use it for the command and telemetry definitions.

## Converting a .xtce file into a COSMOS configuration

Use the following command to convert a .xtce file into COSMOS configuration files. The converted configuration files will be placed into a target folder in the given output directory.

```
openc3.sh cli xtce_converter --import <xtce_filename> --output <output_dir>
```

Add `--validate` to check the file against the XTCE 1.2 schema before importing it. The result is reported and the import proceeds either way, because COSMOS accepts more than the 1.2 schema does: a valid XTCE 1.0 file imports correctly while reporting errors against 1.2. A file declaring an older namespace is not measured against the 1.2 schema at all, it just says so and moves on.

## Converting a COSMOS Configuration to XTCE

Use the following command to convert your openc3 plugin into .xtce files, one per target. The converted .xtce files will be placed into a target folder in the given output directory.

```
openc3.sh cli xtce_converter --plugin <plugin.gem> --output <output_dir>
```

Exported files are validated against the XTCE 1.2 schema and an invalid file fails the export with a non-zero exit code, so a config that COSMOS cannot express in valid XTCE is reported here rather than by whatever ground system the file was written for. Pass `--no-validate` to write the files anyway.

Validation is entirely offline and works in an air gapped system. The OMG schemas ship inside the gem (`data/xtce_schemas`) and validation reads them from there. Exported files still declare an omg.org URL in `schemaLocation`, but that is only a hint for other ground systems reading the file; COSMOS never fetches it.

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
- ReferenceTime
- Epoch
- AncillaryDataSet
- AncillaryData
- ErrorDetectCorrect - the item is read as an unsigned integer and the CRC is not calculated
- AliasSet / Alias - except for an `Alias` in the `COSMOS` namespace on a `Parameter` or an `Argument`, which restores the original COSMOS item name (see below)

## Item Name Round Trip

XTCE forbids characters COSMOS allows in an item name, and a command ID item is
prefixed with `CMD_` so it cannot collide with a telemetry parameter of the same
name. Whenever the exporter has to write a different name it records the original in
an `Alias` in the `COSMOS` namespace, and the importer restores it, so `CMD_ID` comes
back as `ID` and `CMD_0__ATTRIBUTES_ID` as `CMD[0].ATTRIBUTES/ID`. Aliases COSMOS also
writes on `SequenceContainer`, `MetaCommand` and `SpaceSystem` are not restored,
because a packet is registered under its name as soon as it is created.

## Unsupported Elements

Any elements not listed above are currently unsupported. Near term support for the following elements and features are planned and priority will be determined by user requests.

- SplineCalibrator
- AbsoluteTimeParameterType / AbsoluteTimeArgumentType and the relative time types
- Multi-dimensional arrays
- `nextEntry` entry offsets (`containerStart`, `containerEnd` and `previousEntry` are supported)
- Output to the XUSP standard
- Additional Data Types

If there is a particular element or feature you need supported please submit a ticket on Github.
