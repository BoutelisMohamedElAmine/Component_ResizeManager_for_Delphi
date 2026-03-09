unit ResizeManager;

interface

uses
  System.Classes, System.SysUtils, System.Types, System.Generics.Collections,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics;

type
  TAutoResizeItem = class
  private
    FControl: TControl;
    FOriginalRect: TRect;
    FOriginalParentWidth: Integer;
    FOriginalParentHeight: Integer;
  public
    property Control: TControl read FControl;
  end;

  TAutoResizeManager = class(TComponent)
  private
    FForm: TForm;
    FItems: TObjectList<TAutoResizeItem>;
    FOriginalFormWidth: Integer;
    FOriginalFormHeight: Integer;
    FEnabled: Boolean;
    FAutoRegister: Boolean;
    FMinWidth: Integer;
    FMinHeight: Integer;
    FDelayResize: Boolean;
    FResizeDelay: Integer;
    FOnBeforeResize: TNotifyEvent;
    FOnAfterResize: TNotifyEvent;
    FResizeTimer: TComponent; // TTimer غير متوفر في VCL بدون ExtCtrls

    procedure SetForm(const Value: TForm);
    procedure SetEnabled(const Value: Boolean);
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure SaveControlState(AControl: TControl);
    procedure ApplyResize;
    procedure ScheduleResize;

  protected
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure RegisterControl(AControl: TControl);
    procedure UnregisterControl(AControl: TControl);
    procedure RegisterAllControls;

    procedure ResetLayout;
    procedure UpdateLayout;

  published
    property Form: TForm read FForm write SetForm;
    property Enabled: Boolean read FEnabled write SetEnabled default True;
    property AutoRegister: Boolean read FAutoRegister write FAutoRegister default True;
    property MinWidth: Integer read FMinWidth write FMinWidth default 320;
    property MinHeight: Integer read FMinHeight write FMinHeight default 240;
    property ResizeDelay: Integer read FResizeDelay write FResizeDelay default 100;

    property OnBeforeResize: TNotifyEvent read FOnBeforeResize write FOnBeforeResize;
    property OnAfterResize: TNotifyEvent read FOnAfterResize write FOnAfterResize;
  end;

procedure Register;

implementation

uses
  System.Math, Vcl.ExtCtrls;

procedure Register;
begin
  RegisterComponents('Auto Size', [TAutoResizeManager]);
end;

{ TAutoResizeManager }

constructor TAutoResizeManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FItems := TObjectList<TAutoResizeItem>.Create(True);
  FEnabled := True;
  FAutoRegister := True;
  FMinWidth := 320;
  FMinHeight := 240;
  FResizeDelay := 100;
  FDelayResize := True;
  FResizeTimer := nil;

  // إذا كان المالك Form، نربطه تلقائياً
  if AOwner is TForm then
    Form := TForm(AOwner);
end;

destructor TAutoResizeManager.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TAutoResizeManager.SetForm(const Value: TForm);
begin
  if FForm <> Value then
  begin
    if FForm <> nil then
    begin
      FForm.RemoveFreeNotification(Self);
      FForm.OnResize := nil;
      FForm.OnShow := nil;
    end;

    FForm := Value;

    if FForm <> nil then
    begin
      FForm.FreeNotification(Self);
      FOriginalFormWidth := FForm.ClientWidth;
      FOriginalFormHeight := FForm.ClientHeight;

      FForm.OnResize := FormResize;
      FForm.OnShow := FormShow;

      // تسجيل جميع عناصر النموذج تلقائياً
      if FAutoRegister then
        RegisterAllControls;
    end;
  end;
end;

procedure TAutoResizeManager.SetEnabled(const Value: Boolean);
begin
  FEnabled := Value;
end;

procedure TAutoResizeManager.FormShow(Sender: TObject);
begin
  // عند ظهور النموذج، نحفظ حالة جميع العناصر
  if FOriginalFormWidth = 0 then
  begin
    FOriginalFormWidth := FForm.ClientWidth;
    FOriginalFormHeight := FForm.ClientHeight;

    if FAutoRegister then
      RegisterAllControls;
  end;
end;

procedure TAutoResizeManager.FormResize(Sender: TObject);
begin
  if FEnabled then
  begin
    if FDelayResize and (FResizeDelay > 0) then
      ScheduleResize
    else
      ApplyResize;
  end;
end;

procedure TAutoResizeManager.ScheduleResize;
begin
  // إلغاء أي مؤقت سابق
  if FResizeTimer <> nil then
    FResizeTimer.Free;

  // إنشاء مؤقت بسيط باستخدام TThread
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(FResizeDelay);
      TThread.Synchronize(nil,
        procedure
        begin
          ApplyResize;
        end
      );
    end
  ).Start;
end;

procedure TAutoResizeManager.SaveControlState(AControl: TControl);
var
  Item: TAutoResizeItem;
  I: Integer;
begin
  // التحقق من عدم التسجيل المكرر
  for I := 0 to FItems.Count - 1 do
  begin
    if FItems[I].FControl = AControl then
      Exit;
  end;

  // إنشاء عنصر جديد
  Item := TAutoResizeItem.Create;
  Item.FControl := AControl;
  Item.FOriginalRect := Rect(
    AControl.Left,
    AControl.Top,
    AControl.Left + AControl.Width,
    AControl.Top + AControl.Height
  );

  if AControl.Parent is TWinControl then
  begin
    Item.FOriginalParentWidth := TWinControl(AControl.Parent).ClientWidth;
    Item.FOriginalParentHeight := TWinControl(AControl.Parent).ClientHeight;
  end
  else
  begin
    Item.FOriginalParentWidth := 0;
    Item.FOriginalParentHeight := 0;
  end;

  FItems.Add(Item);
  AControl.FreeNotification(Self);
end;

procedure TAutoResizeManager.RegisterControl(AControl: TControl);
begin
  if (AControl <> nil) and (FForm <> nil) then
    SaveControlState(AControl);
end;

procedure TAutoResizeManager.UnregisterControl(AControl: TControl);
var
  I: Integer;
begin
  for I := FItems.Count - 1 downto 0 do
  begin
    if FItems[I].FControl = AControl then
    begin
      FItems.Delete(I);
      Break;
    end;
  end;
end;

procedure TAutoResizeManager.RegisterAllControls;

  procedure ProcessControl(Parent: TWinControl);
  var
    I: Integer;
  begin
    if Parent = nil then
      Exit;

    for I := 0 to Parent.ControlCount - 1 do
    begin
      // تسجيل العنصر
      SaveControlState(Parent.Controls[I]);

      // معالجة العناصر الفرعية إن وجدت
      if Parent.Controls[I] is TWinControl then
        ProcessControl(TWinControl(Parent.Controls[I]));
    end;
  end;

begin
  if FForm = nil then
    Exit;

  FItems.Clear;
  ProcessControl(FForm);
end;

procedure TAutoResizeManager.ApplyResize;
var
  Item: TAutoResizeItem;
  ScaleX, ScaleY: Double;
  NewLeft, NewTop, NewWidth, NewHeight: Integer;
  I: Integer;
begin
  if (FForm = nil) or not FEnabled or (FItems.Count = 0) then
    Exit;

  // تطبيق الحد الأدنى للنموذج
  if (FMinWidth > 0) and (FForm.ClientWidth < FMinWidth) then
    FForm.ClientWidth := FMinWidth;

  if (FMinHeight > 0) and (FForm.ClientHeight < FMinHeight) then
    FForm.ClientHeight := FMinHeight;

  // استدعاء الحدث قبل التحجيم
  if Assigned(FOnBeforeResize) then
    FOnBeforeResize(Self);

  // حساب عوامل التحجيم
  if FOriginalFormWidth > 0 then
    ScaleX := FForm.ClientWidth / FOriginalFormWidth
  else
    ScaleX := 1;

  if FOriginalFormHeight > 0 then
    ScaleY := FForm.ClientHeight / FOriginalFormHeight
  else
    ScaleY := 1;

  // تطبيق التحجيم على جميع العناصر
  for I := 0 to FItems.Count - 1 do
  begin
    Item := FItems[I];

    if (Item.FControl = nil) or not Item.FControl.Visible then
      Continue;

    // حساب الأبعاد الجديدة
    NewLeft := Round(Item.FOriginalRect.Left * ScaleX);
    NewTop := Round(Item.FOriginalRect.Top * ScaleY);
    NewWidth := Round((Item.FOriginalRect.Right - Item.FOriginalRect.Left) * ScaleX);
    NewHeight := Round((Item.FOriginalRect.Bottom - Item.FOriginalRect.Top) * ScaleY);

    // تطبيق الأبعاد الجديدة
    Item.FControl.SetBounds(NewLeft, NewTop, NewWidth, NewHeight);
  end;

  // استدعاء الحدث بعد التحجيم
  if Assigned(FOnAfterResize) then
    FOnAfterResize(Self);
end;

procedure TAutoResizeManager.ResetLayout;
var
  Item: TAutoResizeItem;
begin
  if FForm = nil then
    Exit;

  FOriginalFormWidth := FForm.ClientWidth;
  FOriginalFormHeight := FForm.ClientHeight;

  for Item in FItems do
  begin
    if Item.FControl <> nil then
    begin
      Item.FOriginalRect := Rect(
        Item.FControl.Left,
        Item.FControl.Top,
        Item.FControl.Left + Item.FControl.Width,
        Item.FControl.Top + Item.FControl.Height
      );
    end;
  end;
end;

procedure TAutoResizeManager.UpdateLayout;
begin
  ApplyResize;
end;

procedure TAutoResizeManager.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if Operation = opRemove then
  begin
    if AComponent = FForm then
      FForm := nil
    else if AComponent is TControl then
      UnregisterControl(TControl(AComponent));
  end;
end;

end.
