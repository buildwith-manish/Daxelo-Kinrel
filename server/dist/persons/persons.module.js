"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PersonsModule = void 0;
const common_1 = require("@nestjs/common");
const persons_controller_1 = require("./persons.controller");
const persons_service_1 = require("./persons.service");
let PersonsModule = class PersonsModule {
};
exports.PersonsModule = PersonsModule;
exports.PersonsModule = PersonsModule = __decorate([
    (0, common_1.Module)({
        controllers: [persons_controller_1.PersonsController, persons_controller_1.PersonController],
        providers: [persons_service_1.PersonsService],
        exports: [persons_service_1.PersonsService],
    })
], PersonsModule);
//# sourceMappingURL=persons.module.js.map