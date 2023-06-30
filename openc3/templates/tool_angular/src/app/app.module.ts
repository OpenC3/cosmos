import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { PortalModule } from '@angular/cdk/portal';

import { AppRoutingModule } from './app-routing.module';
import { AppComponent } from './app.component';
import {MatCardModule} from '@angular/material/card';
import {MatButtonModule} from '@angular/material/button';
import {MatMenuModule} from '@angular/material/menu';
import {OverlayContainer} from '@angular/cdk/overlay';
import {AppOverlayContainer} from './custom-overlay-container';

@NgModule({
  declarations: [
    AppComponent
  ],
  imports: [
    BrowserModule,
    AppRoutingModule,
    PortalModule,
    MatCardModule,
    MatButtonModule,
    MatMenuModule
  ],
  providers: [
    { provide: OverlayContainer, useClass: AppOverlayContainer },
  ],
  bootstrap: [AppComponent]
})
export class AppModule { }
