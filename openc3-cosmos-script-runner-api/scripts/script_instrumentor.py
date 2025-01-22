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
import sys


# For details on the AST, see https://docs.python.org/3/library/ast.html
# and https://greentreesnakes.readthedocs.io/en/latest/nodes.html


# This class is used to instrument a Python script with calls to a
# RunningScript instance. The RunningScript instance is used to
# track the execution of the script, and can be used to pause and
# resume the script. We inherit from ast.NodeTransformer, which
# allows us to modify the AST of the script.  We override the visit
# method for each type of node that we want to instrument.
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
        self.try_nodes = [ast.Try]
        if sys.version_info >= (3, 11):
            self.try_nodes.append(ast.TryStar)

    # What we're trying to do is wrap executable statements in a while True try/except block
    # For example if the input code is "print('HI')", we want to transform it to:
    # while True:
    #     try:
    #         RunningScript.instance.pre_line_instrumentation('myfile.py', 1, globals(), locals())
    #     --> print('HI') <-- This is the original node
    #         break
    #     except:
    #         retry_needed = RunningScript.instance.exception_instrumentation('myfile.py', 1)
    #         if retry_needed:
    #             continue
    #         else:
    #             break
    #     finally:
    #         RunningScript.instance.post_line_instrumentation('myfile.py', 1)
    # This allows us to retry statements that raise exceptions
    def track_enter_leave(self, node):
        # Determine if we're in a try block
        in_try = self.in_try
        if not in_try and type(node) in self.try_nodes:
            self.in_try = True
        # Visit the children of the node
        node = self.generic_visit(node)
        if not in_try and type(node) in self.try_nodes:
            self.in_try = False
        # ast.parse returns a module, so we need to extract
        # the first element of the body which is the node
        pre_line = ast.parse(
            self.pre_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        post_line = ast.parse(
            self.post_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        true_node = ast.Constant(True)
        break_node = ast.Break()
        for new_node in (pre_line, post_line, true_node, break_node):
            # Copy source location from the original node to our new nodes
            ast.copy_location(new_node, node)

        # Create the exception handler code node. This results in multiple nodes
        # because we have a top level assignment and if statement
        exception_handler = ast.parse(
            self.exception_instrumentation.format(self.filename, node.lineno)
        ).body
        for new_node in exception_handler:
            ast.copy_location(new_node, node)
            # Recursively yield the children of the new_node and copy in source locations
            # It's actually surprising how many nodes are nested in the new_node
            for new_node2 in ast.walk(new_node):
                ast.copy_location(new_node2, node)
        # Create an exception handler node to wrap the exception handler code
        excepthandler = ast.ExceptHandler(type=None, name=None, body=exception_handler)
        ast.copy_location(excepthandler, node)
        # If we're not already in a try block, we need to wrap the node in a while loop
        if not self.in_try:
            try_node = ast.Try(
                # pre_line is the pre_line_instrumentation, node is the original node
                # and if the code is executed without an exception, we break
                body=[pre_line, node, break_node],
                # Pass in the handler we created above
                handlers=[excepthandler],
                # No else block
                orelse=[],
                # The try / except finally block is the post_line_instrumentation
                finalbody=[post_line],
            )
            ast.copy_location(try_node, node)
            while_node = ast.While(test=true_node, body=[try_node], orelse=[])
            ast.copy_location(while_node, node)
            return while_node
        # We're already in a try block, so we just need to wrap the node in a try block
        else:
            try_node = ast.Try(
                body=[pre_line, node],
                handlers=[],
                orelse=[],
                finalbody=[post_line],
            )
            ast.copy_location(try_node, node)
            return try_node

    # Call the pre_line_instrumentation ONLY and then execute the node
    def track_reached(self, node):
        # Determine if we're in a try block, this is used by track_enter_leave
        in_try = self.in_try
        if not in_try and type(node) in self.try_nodes:
            self.in_try = True

        # Visit the children of the node
        node = self.generic_visit(node)
        pre_line = ast.parse(
            self.pre_line_instrumentation.format(self.filename, node.lineno)
        ).body[0]
        ast.copy_location(pre_line, node)

        # Create a simple constant node with the value 1 that we can use with our If node
        n = ast.Constant(value=1)
        ast.copy_location(n, node)
        # The if_node is effectively a noop that holds the preline & node that we need to execute
        if_node = ast.If(test=n, body=[pre_line, node], orelse=[])
        ast.copy_location(if_node, node)
        return if_node

    def track_import_from(self, node):
        # Don't tract from __future__ imports because they must come first or:
        #   SyntaxError: from __future__ imports must occur at the beginning of the file
        if node.module != '__future__':
            return self.track_enter_leave(node)

    # Notes organized (including newlines) per https://docs.python.org/3/library/ast.html#abstract-grammar
    # Nodes that change control flow are processed by track_reached, otherwise we track_enter_leave
    visit_FunctionDef = track_reached
    visit_AsyncFunctionDef = track_reached

    visit_ClassDef = track_reached
    visit_Return = track_reached

    visit_Delete = track_enter_leave
    visit_Assign = track_enter_leave
    visit_TypeAlias = track_enter_leave
    visit_AugAssign = track_enter_leave
    visit_AnnAssign = track_enter_leave

    visit_For = track_reached
    visit_AsyncFor = track_reached
    visit_While = track_reached
    visit_If = track_reached
    visit_With = track_reached
    visit_AsyncWith = track_reached

    # We can track the match statement but not any of the case statements
    # because they must come unaltered after the match statement
    visit_Match = track_reached

    visit_Raise = track_enter_leave
    visit_Try = track_reached
    if sys.version_info >= (3, 11):
        visit_TryStar = track_reached
    visit_Assert = track_enter_leave

    visit_Import = track_enter_leave
    visit_ImportFrom = track_import_from

    visit_Global = track_enter_leave
    visit_Nonlocal = track_enter_leave
    visit_Expr = track_enter_leave
    visit_Pass = track_reached
    visit_Break = track_reached
    visit_Continue = track_reached

    # expr nodes: mostly subnodes in assignments or return statements
    # TODO: Should we handle the following:
    # visit_NamedExpr = track_enter_leave
    # visit_Lambda = track_enter_leave
    # visit_IfExp = track_enter_leave
    # visit_Await = track_reached
    # visit_Yield = track_reached
    # visit_YieldFrom = track_reached
    # visit_Call = track_reached
    # visit_JoinedStr = track_enter_leave
    # visit_Constant = track_enter_leave

    # All the expr_context, boolop, operator, unaryop, cmpop nodes are not modified
    # ExceptHandler must follow try or tryStar so don't modify it
    # Can't modify any of pattern nodes (case) because they have to come unaltered after match
    # Ignore the type_ignore and type_param nodes
