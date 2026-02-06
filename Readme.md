# InnoCallback (Inno Setup 6.7 / Delphi 13)

`InnoCallback.dll` добавляет совместимый экспорт `wrapcallback`, который превращает script-метод Inno Setup в нативный callback-указатель для WinAPI/DLL (stdcall).

## Важно

В Inno Setup v6.7.0 уже есть встроенный `CreateCallback`. Для новых скриптов предпочтителен именно он.

Этот проект нужен как compatibility layer, если:
- у вас уже есть скрипты/интеграции с `wrapcallback`;
- требуется drop-in замена без переписывания существующего кода.

## Что обновлено

- совместимость с Delphi 13 (современные RTL-модули и типы `NativeInt/NativeUInt`);
- поддержка `CPUX86` и `CPUX64` в генерации callback thunk;
- удалён legacy-конфиг Delphi 7;
- обновлены примеры `.iss` под Inno Setup 6.7.

## Экспорт

```pascal
function WrapCallback(Proc: TMethod; ParamCount: Integer): NativeInt; stdcall;
exports
  WrapCallback name 'wrapcallback';
```

## Примеры

- `innocallbackexample.iss` — таймер WinAPI через callback из скрипта.
- `innocallbacktest.iss` — тест через `EnumWindows`.
- `innocallbackexperiment.iss` — сравнение `wrapcallback` и встроенного `CreateCallback`.
