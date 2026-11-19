// b_train.lir'in birebir C ikizi: ayni 3 katman (128->256->256->16), ayni K=8,
// ayni 5000 adim, ayni forward VE ayni learn (gradyan + tau + agirlik guncellemesi).
//
// Neden ayri bir ikiz: ai/bench/c_twin.c yalnizca forward() yapiyor, learn()
// hic yok. Onunla olculen "20.6x" elmayla-armut karsilastirmasiydi; orada LIR
// tarafi 5000 adimda learn de calistiriyordu. Bu dosya ayni isi yapiyor.
// Aritmetik ai/src/fixed.lir ve ai/src/ledger.lir ile birebir ayni tutuldu.
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#define K 8
#define EDGE_STRIDE 4
#define ONE 4294967296LL
#define MAXV 4611686018427387904LL
#define SENT 9223372036854775807LL
static inline int64_t sat_add(int64_t a,int64_t b){int64_t s=a+b;
 if((a>=0)==(b>=0)&&((a>=0)!=(s>=0)))return a>=0?MAXV:-MAXV;return s;}
static inline int64_t mul(int64_t a,int64_t b){return ((a>>16)*(b>>16));}
static inline int64_t mul_sat(int64_t a,int64_t b){
 if(a==0||b==0)return 0; int64_t as=a>>16,bs=b>>16;
 if(as>=ONE*2||as<=-ONE*2||bs>=ONE*2||bs<=-ONE*2)return (a>=0)==(b>=0)?MAXV:-MAXV;
 return as*bs;}
static inline int64_t lrelu(int64_t x){return x<0?(x>>4)+16777216:x+16777216;}
static inline int64_t clamp_i(int64_t v,int64_t lo,int64_t hi){return v<lo?lo:(v>hi?hi:v);}
static inline int64_t energy_scale(int64_t e){return e>>4;}
static inline int64_t div_q(int64_t a,int64_t b){return (a<<32)/b;}
typedef struct{int64_t*edges;int64_t*bias;int64_t*out;int64_t nin,nout,k;}L;
static void fwd(L*b,const int64_t*x){int64_t nout=b->nout,k=b->k;int64_t*e=b->edges;
 for(int64_t o=0;o<nout;o++){int64_t acc=b->bias[o];
  int64_t obase=o*k*EDGE_STRIDE;
  for(int64_t j=0;j<k;j++){int64_t eb=obase+j*EDGE_STRIDE;
   int64_t i=e[eb],w=e[eb+1],xv=x[i];acc=sat_add(acc,mul(w,xv));}
  b->out[o]=lrelu(acc);}}
static int64_t learn(L*b,const int64_t*x,const int64_t*t,int64_t eta){
 int64_t nout=b->nout,k=b->k;int64_t*e=b->edges;int64_t total=0;
 for(int64_t o=0;o<nout;o++){
  int64_t yhat=b->out[o],tv=t[o],d=tv-yhat,e2=mul_sat(d,d);total=sat_add(total,e2);
  if(d!=0){int64_t obase=o*k*EDGE_STRIDE;
   int64_t nrm=ONE;
   for(int64_t j=0;j<k;j++){int64_t i=e[obase+j*EDGE_STRIDE];int64_t xv=x[i];nrm=sat_add(nrm,mul(xv,xv));}
   int64_t inv=div_q(ONE,nrm);
   int64_t g=mul(mul(eta,d),inv);
   int64_t ti=energy_scale(e2);
   for(int64_t j2=0;j2<k;j2++){int64_t eb=obase+j2*EDGE_STRIDE;
    int64_t i2=e[eb],xv2=x[i2];int64_t delta=mul(g,xv2);
    e[eb+1]=clamp_i(sat_add(e[eb+1],delta),-MAXV,MAXV);
    int64_t t2=e[eb+2];int64_t tn=sat_add(t2,ti);
    e[eb+2]=(tn>1000000LL*ONE)?1000000LL*ONE:tn;
    e[eb+3]=e[eb+3]+1;}
   b->bias[o]=clamp_i(sat_add(b->bias[o],g),-MAXV,MAXV);}}
 return total;}
int main(void){
 int64_t n1=128,n2=256,n3=16;
 int64_t*x=malloc(n1*8),*h1=malloc(n2*8),*h2=malloc(n2*8),*t=malloc(n3*8);
 for(int64_t i=0;i<n1;i++)x[i]=i%11;
 for(int64_t i=0;i<n3;i++)t[i]=ONE;
 L a,b,c;int64_t nouts[3]={n2,n2,n3};int64_t nins[3]={n1,n2,n2};L*ls[3]={&a,&b,&c};
 for(int l=0;l<3;l++){int64_t no=nouts[l];ls[l]->nout=no;ls[l]->k=K;ls[l]->nin=nins[l];
  ls[l]->edges=malloc(no*K*EDGE_STRIDE*8);ls[l]->bias=malloc(no*8);ls[l]->out=malloc(no*8);
  for(int64_t i=0;i<no*K;i++){ls[l]->edges[i*EDGE_STRIDE]=(i+i/K*5+3)%nins[l];
   ls[l]->edges[i*EDGE_STRIDE+1]=(int64_t)(((i*131)%256)-128)*(1LL<<24);
   ls[l]->edges[i*EDGE_STRIDE+2]=0;ls[l]->edges[i*EDGE_STRIDE+3]=0;}
  for(int64_t o=0;o<no;o++)ls[l]->bias[o]=0;}
 int64_t eta=div_q(1LL*ONE,2*ONE);
 for(int64_t s=0;s<5000;s++){
  fwd(&a,x);for(int64_t q=0;q<n2;q++)h1[q]=a.out[q];
  fwd(&b,h1);for(int64_t q=0;q<n2;q++)h2[q]=b.out[q];
  fwd(&c,h2);learn(&c,h2,t,eta);}
 printf("%lld\n",(long long)(c.out[0]&1023));return 0;}
