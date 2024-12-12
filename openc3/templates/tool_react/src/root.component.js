import React from "react";
import { createPortal } from "react-dom";
import Button from "@mui/material/Button";
import Card from "@mui/material/Card";
import CardContent from "@mui/material/CardContent";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import { OpenC3Api } from "@openc3/js-common/services";

export default function Root(props) {
  const [anchorEl, setAnchorEl] = React.useState();
  const open = Boolean(anchorEl);
  const handleClick = (event) => {
    setAnchorEl(event.currentTarget);
  };
  const sendCommand = () => {
    let api = new OpenC3Api();
    api.cmd("INST", "COLLECT", { TYPE: "NORMAL" }).then((response) => {
      alert("Command Sent!");
    });
  };
  const handleClose = () => {
    setAnchorEl(null);
    sendCommand();
  };

  document.title = "<%= tool_name_display %>";

  return (
    <Card variant="outlined">
      <CardContent>
        <Button variant="contained" onClick={sendCommand}>
          Send Command!
        </Button>
      </CardContent>
      {createPortal(
        <div>
          <Button
            id="basic-button"
            aria-controls={open ? "basic-menu" : undefined}
            aria-haspopup="true"
            aria-expanded={open ? "true" : undefined}
            onClick={handleClick}
            variant="contained"
            disableElevation
          >
            File
          </Button>
          <Menu
            id="basic-menu"
            anchorEl={anchorEl}
            open={open}
            onClose={handleClose}
            MenuListProps={{
              "aria-labelledby": "basic-button",
            }}
          >
            <MenuItem onClick={handleClose}>Send Command</MenuItem>
          </Menu>
          <div
            style={{
              "align-items": "center",
              "text-align": "center",
              width: "80%",
              display: "inline-flex",
              position: "relative",
              "z-index": 0,
              padding: "4px 16px",
            }}
          >
            <div
              style={{
                "font-size": "1.25rem",
                "line-height": 1.5,
                "text-overflow": "ellipsis",
                "white-space": "nowrap",
                width: "100%",
              }}
            >
              <%= tool_name_display %>
            </div>
          </div>
        </div>,
        document.getElementById("openc3-menu")
      )}
    </Card>
  );
}
