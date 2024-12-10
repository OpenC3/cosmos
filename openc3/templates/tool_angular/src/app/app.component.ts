import { Component, ViewChild, AfterViewInit, OnDestroy } from '@angular/core';
import {CdkPortal, DomPortalOutlet} from '@angular/cdk/portal';
import { OpenC3Api } from "@openc3/js-common/services";

@Component({
  selector: 'openc3-tool-<%= tool_name %>-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss'],
})
export class AppComponent implements  AfterViewInit, OnDestroy {
  @ViewChild(CdkPortal)
  private portal: CdkPortal | undefined;
  private host: DomPortalOutlet | undefined;

  clickHandler = function() {
    let api = new OpenC3Api();
    api.cmd("INST", "COLLECT", { TYPE: "NORMAL" }).then((response: any) => {
      alert("Command Sent!");
    });
  }
  getMenuElement() {
    let elem = document.getElementById("openc3-menu")
    if (elem) {
      return elem
    } else {
      return new HTMLElement()
    }
  }
  ngAfterViewInit(): void {
    this.host = new DomPortalOutlet(
      this.getMenuElement()
    );
    this.host.attach(this.portal);
    document.title = "<%= tool_name_display %>";
    let tool = document.querySelector('#openc3-tool');
    if (tool == null) {
      tool = new HTMLElement()
    }
    let overlay = document.querySelector('.cdk-overlay-container');
    if (overlay == null) {
      overlay = new HTMLElement()
    }
    // Move stuff
    tool.append(overlay);
  }
  ngOnDestroy(): void {
    if (this.host) {
      this.host.detach();
    }
  }
}
