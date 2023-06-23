<div style="min-width: 100px;">
  <Card variant="outlined" padded>
    <Button on:click={() => handleClick()} variant="raised">
      <Label>Send Command</Label>
    </Button>
  </Card>
</div>

<Portal target="#openc3-menu">
  <Button on:click={() => menu.setOpen(true)} variant="raised">
    <Label>File</Label>
  </Button>
  <Menu bind:this={menu}>
    <List>
      <Item on:SMUI:action={() => handleClick()}>
        <Text>Send Command</Text>
      </Item>
    </List>
  </Menu>

  <div style="display: inline-block; text-align: center; width:80%;"><%= tool_name_display %></div>
</Portal>

<script>
  import Portal from "svelte-portal";
  import Menu from '@smui/menu';
  import List, { Item, Separator, Text } from '@smui/list';
  import Button, { Label } from '@smui/button';
  import Card from '@smui/card';
  import { OpenC3Api } from "./services/openc3-api";

  let menu;

  function handleClick () {
    let api = new OpenC3Api();
    api.cmd("INST", "COLLECT", { TYPE: "NORMAL" }).then((response) => {
      alert("Command Sent!");
    });
	}

  document.title = "<%= tool_name_display %>";
</script>