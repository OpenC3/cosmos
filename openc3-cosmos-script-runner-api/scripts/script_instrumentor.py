# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import ast


class ScriptInstrumentor(ast.NodeTransformer):
    pre_line_instrumentation = """
RunningScript.instance.pre_line_instrumentation('{}', {}, globals(), locals())
    """

    post_line_instrumentation = """
RunningScript.instance.post_line_instrumentation('{}', {})
    """

    exception_instrumentation = """
retry_needed = RunningScript.instance.exception_instrumentation('{}', {})
if retry_needed:
    continue
else:
    break
    """

    def __init__(self, filename):
        self.filename = filename
        self.in_try = False

    # These are statements which should have an enter and leave
    # (In retrospect, this isn't always true, eg, for 'if')
    def track_enter_leave_lineno(self, node):
        in_try = self.in_try
        if not in_try and type(node) in (ast.Try, ast.TryStar):
            self.in_try = True
        node = self.generic_visit(node)
        if not in_try and type(node) in (ast.Try, ast.TryStar):
            self.in_try = False
        enter = ast.parse(
            self.pre_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        leave = ast.parse(
            self.post_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        true_node = ast.Constant(True)
        break_node = ast.Break()
        for new_node in (enter, leave, true_node, break_node):
            ast.copy_location(new_node, node)

        # This is the code for "if 1: ..."
        inhandler = ast.parse(
            self.exception_instrumentation.format(self.filename, node.lineno)
        ).body
        for new_node in inhandler:
            ast.copy_location(new_node, node)
            for new_node2 in ast.walk(new_node):
                ast.copy_location(new_node2, node)
        excepthandler = ast.ExceptHandler(expr=None, name=None, body=inhandler)
        ast.copy_location(excepthandler, node)
        if not self.in_try:
            try_node = ast.Try(
                body=[enter, node, break_node],
                handlers=[excepthandler],
                orelse=[],
                finalbody=[leave],
            )
            ast.copy_location(try_node, node)
            while_node = ast.While(test=true_node, body=[try_node], orelse=[])
            ast.copy_location(while_node, node)
            return while_node
        else:
            try_node = ast.Try(
                body=[enter, node],
                handlers=[],
                orelse=[],
                finalbody=[leave],
            )
            ast.copy_location(try_node, node)
            return try_node

    visit_FunctionDef = track_enter_leave_lineno
    visit_ClassDef = track_enter_leave_lineno
    visit_Assign = track_enter_leave_lineno
    visit_AugAssign = track_enter_leave_lineno
    visit_Delete = track_enter_leave_lineno
    visit_Print = track_enter_leave_lineno
    visit_For = track_enter_leave_lineno
    visit_While = track_enter_leave_lineno
    visit_If = track_enter_leave_lineno
    visit_With = track_enter_leave_lineno
    visit_Try = track_enter_leave_lineno
    visit_TryStar = track_enter_leave_lineno
    visit_Assert = track_enter_leave_lineno
    visit_Import = track_enter_leave_lineno
    visit_ImportFrom = track_enter_leave_lineno
    visit_Exec = track_enter_leave_lineno
    # Global
    visit_Expr = track_enter_leave_lineno
    visit_Pass = track_enter_leave_lineno

    # These statements can be reached, but they change
    # control flow and are never exited.
    def track_reached_lineno(self, node):
        node = self.generic_visit(node)
        reach = ast.parse(
            self.pre_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        ast.copy_location(reach, node)

        n = ast.Num(n=1)
        ast.copy_location(n, node)
        if_node = ast.If(test=n, body=[reach, node], orelse=[])
        ast.copy_location(if_node, node)
        return if_node

    visit_Return = track_reached_lineno
    visit_Raise = track_enter_leave_lineno
    visit_Break = track_reached_lineno
    visit_Continue = track_reached_lineno
