`timescale 1ns / 1ps

module hygro_i2c(
  input clk,
  input rst,
  input i2c_2clk,//Used to shifting and sampling, max 800kHz
  //Data output
  output reg [13:0] tem,
  output reg [13:0] hum,
  //I2C pins
  output SCL/* synthesis keep = 1 */, 
  inout SDA/* synthesis keep = 1 */);
  
  reg i2c_clk; //390.625kHz
  wire SDA_Claim;
  wire SDA_Write;
  
  //I2C flow control
  wire gettingTEM, gettingHUM;
  reg givingADDRS;
  reg SDA_d;
  reg noMoreByte;
  reg [7:0] SDA_w_buff;
  
  //Module states
  reg [1:0] state; 
  localparam IDLE = 2'b00,
         BEG_MEAS = 2'b01,
             WAIT = 2'b11,
          GET_DAT = 2'b10;
  wire in_IDLE, in_BEG_MEAS, in_WAIT, in_GET_DAT;
  
  //I2C states
  reg [2:0] i2c_state;
  localparam I2C_READY = 3'b000,
             I2C_START = 3'b001,
             I2C_ADDRS = 3'b011,
             I2C_WRITE = 3'b110,
         I2C_WRITE_ACK = 3'b010,
              I2C_READ = 3'b111,
          I2C_READ_ACK = 3'b101,
              I2C_STOP = 3'b100;
  wire I2Cin_READY, I2Cin_START, I2Cin_ADDRS, I2Cin_WRITE, I2Cin_WRITE_ACK, I2Cin_READ, I2Cin_READ_ACK, I2Cin_STOP;
  
  //Initiate I2C transaction
  reg I2Cinit;
  
  //Counters
  reg [2:0] bitCounter; //Count current bit
  reg [1:0] byteCounter; //Count databytes
  
  //Check whether sensor responded
  reg responded;
  
  //Edge detection for i2c_2clk
  reg i2c_2clk_d;
  wire i2c_2clk_negedge;
  
  //I2C decode states and I2C state drived signals
  assign I2Cin_READY = (i2c_state == I2C_READY);
  assign I2Cin_START = (i2c_state == I2C_START);
  assign I2Cin_ADDRS = (i2c_state == I2C_ADDRS);
  assign I2Cin_WRITE = (i2c_state == I2C_WRITE);
  assign I2Cin_WRITE_ACK = (i2c_state == I2C_WRITE_ACK);
  assign I2Cin_READ = (i2c_state == I2C_READ);
  assign I2Cin_READ_ACK = (i2c_state == I2C_READ_ACK);
  assign I2Cin_STOP = (i2c_state == I2C_STOP);
  assign i2c_busy = ~I2Cin_READY;

  //Decode states
  assign in_IDLE = (state == IDLE);
  assign in_BEG_MEAS = (state == BEG_MEAS);
  assign in_WAIT = (state == WAIT);
  assign in_GET_DAT = (state == GET_DAT);

  //SDA content control
  assign dataUpdating = I2Cin_READ | I2Cin_READ_ACK;
  assign gettingTEM = (byteCounter == 2'd0) | ((byteCounter == 2'd1) & (bitCounter < 3'd6));
  assign gettingHUM = (byteCounter == 2'd2) | ((byteCounter == 2'd3) & (bitCounter < 3'd6));

  //I2C signals control
  assign SCL = (I2Cin_READY) ? 1'b1 : i2c_clk;
  assign SDA = (SDA_Claim) ? SDA_Write : 1'bZ;
  assign SDA_Claim = I2Cin_START | I2Cin_ADDRS | I2Cin_WRITE | I2Cin_READ_ACK | I2Cin_STOP;
  always@(negedge i2c_2clk) begin
    SDA_d <= SDA;
  end

  //State transactions
  always@(posedge clk or posedge rst) begin
    if(rst) begin
      state <= IDLE;
    end else case(state)
      IDLE     : state <= I2Cin_READY ? BEG_MEAS : state;
      BEG_MEAS : state <= (I2Cin_WRITE_ACK & SCL & i2c_2clk_negedge) ? ((SDA_d) ? IDLE : WAIT) : state;
      WAIT     : state <= (I2Cin_READY) ? GET_DAT : state;
      GET_DAT  : state <= (I2Cin_STOP) ? WAIT : ((I2Cin_READ) ? IDLE : state);
    endcase
  end

  //sensNR & responded
  always@(posedge clk) begin
    responded <= (responded & ~in_WAIT) | in_GET_DAT;
  end
  
  
  //I2Cinit
  always@(posedge clk or posedge rst) begin
    if(rst) begin
      I2Cinit <= 1'b0;
    end else case(I2Cinit)
      1'b0: I2Cinit <= (in_BEG_MEAS | in_WAIT) & I2Cin_READY;
      1'b1: I2Cinit <= I2Cin_READY;
    endcase
  end
  
  //Edge detection for i2c_2clk
  assign i2c_2clk_negedge = i2c_2clk_d & i2c_2clk;
  always@(posedge clk) begin
    i2c_2clk_d <= i2c_2clk;
  end
  

  //givingADDRS
  always@(posedge clk) begin
    if(I2Cin_START)
      givingADDRS <= 1'b1;
    else if(I2Cin_READ | I2Cin_WRITE | I2Cin_STOP)
      givingADDRS <= 1'b0;
  end
  
  //I2C State transactions
  always@(negedge i2c_2clk or posedge rst) begin
    if(rst) begin
      i2c_state <= I2Cin_READ;
    end else case(i2c_state)
      I2C_READY     :i2c_state <= (I2Cinit & i2c_clk) ? I2C_START : i2c_state;
      I2C_START     : i2c_state <= (~SCL) ? I2C_ADDRS : i2c_state;
      I2C_ADDRS     : i2c_state <= (~SCL & &bitCounter) ? I2C_WRITE_ACK : i2c_state;
      I2C_WRITE_ACK : i2c_state <= (~SCL) ? ((~SDA_d & givingADDRS) ? ((in_WAIT) ?  I2C_WRITE : I2C_READ): I2C_STOP) : i2c_state;
      I2C_WRITE     : i2c_state <= (~SCL & &bitCounter) ? I2C_WRITE_ACK : i2c_state;
      I2C_READ      : i2c_state <= (~SCL & &bitCounter) ? I2C_READ_ACK : i2c_state;
      I2C_READ_ACK  : i2c_state <= (~SCL) ? ((noMoreByte) ? I2C_STOP : I2C_READ) : i2c_state;
      I2C_STOP      : i2c_state <= (SCL) ? I2C_READY : i2c_state;
    endcase
  end
  //noMoreByte
  always@(negedge I2Cin_READ_ACK or posedge I2Cin_ADDRS) begin
    if(I2Cin_ADDRS)
      noMoreByte <= 1'b0;
    else
      noMoreByte <= noMoreByte | (byteCounter == 2'd3);
  end
  

  //Count read bytes
  always@(negedge i2c_2clk) begin //Count during read ack and stop counting when max reached, auto reset while giving address
    byteCounter <= (I2Cin_ADDRS) ? 2'd0 : (byteCounter + {1'd0, (I2Cin_READ_ACK & i2c_clk)});
  end

  //Count Bits
  always@(posedge i2c_clk) begin
    if(I2Cin_READ_ACK | I2Cin_READY | I2Cin_WRITE_ACK)
      bitCounter <= 3'b111;
    else if(I2Cin_ADDRS | I2Cin_READ | I2Cin_WRITE)
      bitCounter <= bitCounter + 3'd1;
  end
  

  //Handle sending addresses
  assign SDA_Write = (I2Cin_READ_ACK | I2Cin_START | I2Cin_STOP) ? (I2Cin_READ_ACK & noMoreByte) : SDA_w_buff[7];
  always@(negedge i2c_2clk) begin
    if(I2Cin_START)
      SDA_w_buff <= {7'b1000000, in_GET_DAT};
    else if(~SCL)
      SDA_w_buff <= {SDA_w_buff[6:0], 1'b0};
  end
  
  //Temperature register
  always@(negedge i2c_2clk or posedge rst) begin
    if(rst) begin
      tem <= 14'd0;
    end else if (i2c_clk & I2Cin_READ) begin
      tem <= (gettingTEM) ? {tem[12:0], SDA}: tem;
    end
  end

  //Humidity register
  always@(negedge i2c_2clk or posedge rst) begin
    if(rst) begin
      hum <= 14'd0;
    end else if (i2c_clk & I2Cin_READ) begin
      hum <= (gettingHUM) ? {hum[12:0], SDA}: hum;
    end
  end

  always@(posedge i2c_2clk or posedge rst) begin
    if(rst) begin
        i2c_clk <= 1'b0;
    end else begin
        i2c_clk <= ~i2c_clk;
    end
  end
endmodule//hygro_lite