import { Injectable, OnDestroy } from '@angular/core';
import { OverlayContainer } from '@angular/cdk/overlay';

export class AppOverlayContainer extends OverlayContainer {

  override _createContainer(): void {
    let container = document.createElement('div');
    container.classList.add('cdk-overlay-container');

    let elem = document.querySelector('#openc3-tool');
    if (!elem) {
      elem = new HTMLElement();
    }
    elem.appendChild(container);
    this._containerElement = container;
  }
}